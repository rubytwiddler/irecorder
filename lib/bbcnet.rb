#
#
#
require 'rubygems'
require 'uri'
require 'nokogiri'
require 'shellwords'
require 'fileutils'
require 'tmpdir'
require 'singleton'
require 'yaml'
require 'Qt'

# my libs
require "cache"
require "logwin"

UrlRegexp = URI.regexp(['rtsp','http'])

#
#
class BBCNet < Qt::Object
    include Singleton

    RtspRegexp = URI.regexp(['rtsp'])
    MmsRegexp = URI.regexp(['mms'])
    DirectStreamRegexp = URI.regexp(['mms', 'rtsp', 'rtmp', 'rtmpt'])


    class CachedRawXMLIO < CachedHttpDiskIO
        def initialize(cacheDuration = 25*60, cacheMax=1)
            super
            @tmpdir = File.join(@tmpdir, 'meta_xml')
            FileUtils.mkdir_p(@tmpdir)
        end

        def tempFileName(url)
            File.join(@tmpdir, url.scan(%r{[^/]+$}).first.gsub(%r/[^\w]/, '_'))
        end
    end

    class CachedMetaInfoIO < CachedObjectDiskIO
        def initialize(cacheDuration = 40*60, cacheMax=200)
            super(cacheDuration, cacheMax)
            @tmpdir = File.join(@tmpdir, 'meta_info')
            FileUtils.mkdir_p(@tmpdir)
        end

        # method finished(reply) will be called when read is finished.
        def directRawRead(pid, method, reply)
            BBCNet::MetaInfo.new(pid).update(method, reply)
        end

        def saveCache(id, data)
            open(id, "w") do |f|
                f.write(Marshal.dump(data.dup.cleanData))
            end
        end

        def self.read(url, onRead)
            pid = BBCNet.extractPid(url)
            self.instance.read(pid, onRead)
        end
    end


    #------------------------------------------------------------------------
    # get stream metadata
    # episode url => pid => xml playlist => version pid (vpid aka. identifier)
    #   => xml stream metadata => wma

    #
    # MetaInfo class
    #
    class MetaInfo
        def self.get(url)
            pid = BBCNet.extractPid(url)
            self.new(pid)
        end

        attr_reader :pid
        Keys = [ :duration, :vpid, :group, :media, :onAirDate, :channel, :title, :summary, \
                 :aacLow, :aacStd, :real, :wma, :streams ]
        # onAirDate format : '2010-08-05T22:00:00Z'
        attr_reader *Keys

        def initialize(pid)
            @pid = pid
            Keys.each do |k|
                s = ('@' + k.to_s).to_sym
                self.instance_variable_set(s, nil)
            end

            @streams = []
        end

        def cleanData
            remove_instance_variable :@onRead
            remove_instance_variable :@reply
            remove_instance_variable :@onReadXmlPlaylist
            @aacLow = @aacLow.dup.cleanData if @aacLow
            @aacStd = @aacStd.dup.cleanData if @aacStd
            @real = @real.dup.cleanData if @real
            @wma = @wma.dup.cleanData if @wma
            @streams = @streams.map do |s| s.dup.cleanData end
            self
        end

        protected

        #
        # read duration, vpid, group, media, onAirDate, channel
        #   from XmlPlaylist
        def readXmlPlaylist(onReadXmlPlaylist)
            if @vpid then
                onReadXmlPlaylist.call(self)
                return
            end
            @onReadXmlPlaylist = onReadXmlPlaylist
#             BBCNet.read("http://www.bbc.co.uk/iplayer/playlist/#{@pid}", \
#                               self.method(:onReadXmlPlaylist))
            CachedRawXMLIO.read("http://www.bbc.co.uk/iplayer/playlist/#{@pid}", \
                              self.method(:onReadXmlPlaylist))
#             onReadXmlPlaylist(IO.read("../tmp/iplayer-playlist-me.xml"))
        end

        def onReadXmlPlaylist(res)
            doc = Nokogiri::XML(res)
            item = doc.at_css("noItems")
            #raise "No Playlist " + item[:reason] if item
            return if item      # error!!!

            item = doc.at_css("item")
            @media = item[:kind].gsub(/programme/i, '')
            @duration = item[:duration].to_i
            @vpid = item[:identifier]
            return unless @vpid

            @group = item[:group]
            title = item.at_css("title")
            if title then
                @title = title.content.to_s
                @summary = doc.at_css("summary").content.to_s
                onAirDate = item.at_css("broadcast")
                @onAirDate =  onAirDate ? BBCNet.getTime(onAirDate.content.to_s) : ''
                channel = item.at_css("service")
                @channel = channel ? channel.content.to_s : ''
            else
                @title = @summary = @onAirDate = @channel = ''
            end
            @onReadXmlPlaylist.call(self)
        end

        #
        #   class StreamInfo
        #
        public
        class StreamInfo
            #  example)    48, wma, time, audio, http://..
            attr_accessor :bitrate, :encoding, :expires, :type, :indirectUrl
            alias       :kind :type

            attr_reader :url
            def update(onUpdated)
                return if @url

                @onUpdated = onUpdated
                BBCNet.getDirectStreamUrl(@indirectUrl, self.method(:onRead))
            end

            def cleanData
                remove_instance_variable :@onUpdated
                self
            end

            protected
            def onRead(url)
                @url = url
                @onUpdated.call(url)
            end
        end

        def readXmlStreamMeta(onRead, reply=nil)
            @onRead = onRead
            @reply = reply
            if @vpid then
                readXml_1
            else
                readXmlPlaylist(self.method(:readXml_1))
            end
        end
        alias :update :readXmlStreamMeta

        def streamInfo(prefered=%w{wma real})
            prefered.each do |name|
                case name.to_s.downcase.to_sym
                when :wma
                    return @wma if @wma
                when :aac
                    return @aacStd if @aacStd
                when :real
                    return @real if @real
                when :aaclow
                    return @aacLow if @aacLow
                end
            end
            nil
        end

        protected
        def readXml_1(dummy)
#             BBCNet.read("http://www.bbc.co.uk/mediaselector/4/mtis/stream/#{@vpid}", \
#                               self.method(:onReadXmlStreamMeta))
            CachedRawXMLIO.read("http://www.bbc.co.uk/mediaselector/4/mtis/stream/#{@vpid}", \
                              self.method(:onReadXmlStreamMeta))
#             onReadXmlStreamMeta(IO.read("../tmp/iplayer-stream-meta-me.xml"))
        end

        def onReadXmlStreamMeta(res)
            doc = Nokogiri::XML(res)
            me = doc.css("media")
            @updateCount = 0
            me.each do |m|
                stmInf = StreamInfo.new
                stmInf.encoding = m[:encoding]  # wma
                stmInf.bitrate = m[:bitrate].to_i    # 48
                expiresStr = m[:expires]
                stmInf.expires = BBCNet.getTime(expiresStr)  if expiresStr
                stmInf.type = m[:kind]          # audio

                con = m.at_css("connection")
                stmInf.indirectUrl = con[:href]
                @streams <<= stmInf

                case stmInf.encoding
                when /\bwma\b/i
                    @wma = stmInf
                when /\baac\b/i
                    if stmInf.bitrate < 64
                        @aacLow = stmInf
                    else
                        @aacStd = stmInf
                    end
                when /\breal\b/i
                    @real = stmInf
                end
                @updateCount += 1
                stmInf.update(self.method(:onReadXmlInfUpdated))
            end
        end

        def onReadXmlInfUpdated(url)
            @updateCount -= 1
            return unless @updateCount == 0

            if @reply then
                @onRead.call(self, @reply)
            else
                @onRead.call(self)
            end
        end
    end



    def self.getTime(str)
        tm = str.match(/(\d{4})-(\d\d)-(\d\d)\w(\d\d):(\d\d):(\d\d)/)
        return Time.at(0) unless tm
        par = ((1..6).inject([]) do |a, n| a << tm[n].to_i end)
        Time.gm( *par )
    end


    #------------------------------------------------------------------------
    #
    #

    # convert epsode Url to console Url
    def self.getPlayerConsoleUrl(url)
       "http://www.bbc.co.uk/iplayer/console/" + extractPid(url)
    end

    # get PID from BBC episode Url
    def self.extractPid(url)
        case url
        when %r!/(?:item|episode|programmes)/([a-z0-9]{8})!
            $1
        when %r!^[a-z0-9]{8}$!
            url
        when %r!\b(b[a-z0-9]{7}\b)!
            $1
        else
            raise "No PID in Url '%s'" % url
        end
    end


    protected
    class RetrievingDirectStreamUrl
        def initialize(url, onRead)
            if url and not url[DirectStreamRegexp] then
                @old = url
                @onRead = onRead
                BBCNet.read(url, self.method(:onReadSearching))
            else
                onRead.call(url)
            end
        end

        def onReadSearching(res)
            url = res[ DirectStreamRegexp ] || res[ UrlRegexp ] || @old
            $log.debug { "new url:#{url},  old url:#{@old}" }
            $log.debug { "no url in response '#{res}'" } unless url[ UrlRegexp ]
            if url != @old and not url[DirectStreamRegexp] then
                @old = url
                BBCNet.read(url, self.method(:onReadSearching))
            else
                @onRead.call(url)
            end
        end

        def self.get(url, onRead)
            RetrievingDirectStreamUrl.new(url, onRead)
        end
    end

    public
    # .asf/.ram => .wma/.ra
    def self.getDirectStreamUrl(url, onRead)
        RetrievingDirectStreamUrl::get(url, onRead)
    end




    #-------------------------------
    #
    #  BBCNet class
    #
    public
    def initialize()
        super
        @manager = Qt::NetworkAccessManager.new(self)
        connect(@manager, SIGNAL('finished(QNetworkReply*)'), self, \
                SLOT('finished(QNetworkReply*)'))
        @methods = {}
    end

    class MethodObject < Qt::Object
        def initialize(method, obj=nil)
            super()
            @method = method
            @obj = obj
        end
        def call(data)
            if @obj then
                @method.call(data, @obj)
            else
                @method.call(data)
            end
        end
    end


    def read(url, onRead, obj=nil)
        request = Qt::NetworkRequest.new(Qt::Url.new(url))
        request.setRawHeader(Qt::ByteArray.new("User-Agent"), \
                             Qt::ByteArray.new(BBCNet::randomUserAgent))
        methodObj = MethodObject.new(onRead, obj)
        request.setOriginatingObject(methodObj)
        @methods[url] = methodObj
#         $log.misc { "BBCNet::read.request : request:#{request}, orgObj:#{request.originatingObject}, url:#{url}" }
        @manager.get(request)
    end

    slots 'finished(QNetworkReply*)'
    def finished(reply)
        data = reply.readAll.data
        request = reply.request
        methodObj = request.originatingObject
        url = reply.url.toString
#         $log.misc { "BBCNet::read.finished : url:#{reply.url.toString} methodObj:#{methodObj}, request:#{request}" }
#         reply.request.originatingObject.call(data)
        unless methodObj then
            $log.warn { "internal failure. lost method object of request url:#{url}" }
            methodObj = @methods[url]       # avoid bug that qt drop originatingObject sometime.
        end
        @methods.delete(url)
        methodObj.call(data)
    end


    def self.read(url, onRead, obj=nil)
        self.instance.read(url, onRead, obj)
    end


    protected
    UserAgentList = [
        'Mozilla/5.0 (X11; U; Linux x86_64; en-US) AppleWebKit/<RAND>.13 (KHTML, like Gecko) Chrome/9.0.<RAND> Safari/<RAND>.1',
        'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/<RAND>.8 (KHTML, like Gecko) Chrome/2.0.178.0 Safari/<RAND>.8',
        'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0; YPC 3.2.0; SLCC1; .NET CLR 2.0.50<RAND>; .NET CLR 3.0.04<RAND>)',
        'Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_4_11; tr) AppleWebKit/<RAND>.4+ (KHTML, like Gecko) Version/4.0dp1 Safari/<RAND>.11.2',
        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50<RAND>; .NET CLR 3.5.30<RAND>; .NET CLR 3.0.30<RAND>; Media Center PC 6.0; InfoPath.2; MS-RTC LM 8)',
        'Mozilla/6.0 (Windows; U; Windows NT 7.0; en-US; rv:1.9.0.8) Gecko/2009032609 Firefox/3.0.9 (.NET CLR 3.5.30<RAND>)',
        ]

    public
    def self.randomUserAgent
        ua = UserAgentList[ rand UserAgentList.length ]
        ua.gsub(/<RAND>/, "%03d" % rand(1000))
    end


    TVChannelRssTbl = [
        ['BBC One', 'bbc_one' ],
        ['BBC Two', 'bbc_two' ],
        ['BBC Three', 'bbc_three' ],
        ['BBC Four', 'bbc_four' ],
        ['CBBC', 'cbbc'],
        ['CBeebies', 'cbeebies'],
        ['BBC News Channel', 'bbc_news24'],
        ['BBC Parliament', 'bbc_parliament'],
        ['BBC HD', 'bbc_hd'],
        ['BBC ALBA', 'bbc_alba'] ]

    RadioChannelRssTbl = [
        ['BBC Radio 1', 'bbc_radio_one'],
        ['BBC 1Xtra', 'bbc_1xtra'],
        ['BBC Radio 2', 'bbc_radio_two'],
        ['BBC Radio 3', 'bbc_radio_three'],
        ['BBC Radio 4', 'bbc_radio_four'],
        ['BBC Radio 5 live', 'bbc_radio_five_live'],
        ['BBC Radio 5 live sports extra', 'bbc_radio_five_live_sports_extra'],
        ['BBC 6 Music', 'bbc_6music'],
        ['BBC Radio 7', 'bbc_7'],
        ['BBC Asian Network', 'bbc_asian_network'],
        ['BBC World service', 'bbc_world_service'],
        ['BBC Radio Scotland', 'bbc_alba/scotland'],
        ['BBC Radio Nan Gàidheal', 'bbc_radio_nan_gaidheal'],
        ['BBC Radio Ulster', 'bbc_radio_ulster'],
        ['BBC Radio Foyle', 'bbc_radio_foyle'],
        ['BBC Radio Wales', 'bbc_radio_wales'],
        ['BBC Radio Cymru', 'bbc_radio_cymru'] ]

    CategoryRssTbl = [
        ['Children\'s', 'childrens'],
        ['Comedy', 'comedy'],
        ['Drama', 'drama'],
        ['Entertainment', 'entertainment'],
        ['Factual', 'factual'],
        ['Films', 'films'],
        ['Music', 'music'],
        ['News', 'news'],
        ['Learning', 'learning'],
        ['Religion & Ethics', 'religion_and_ethics'],
        ['Sport', 'sport'],
        ['Sign Zone', 'signed'],
        ['Audio Described', 'audiodescribed'],
        ['Northern Ireland', 'northern_ireland'],
        ['Scotland', 'scotland'],
        ['Wales', 'wales'] ]

    CategoryNameTbl = CategoryRssTbl.map do |c|
            c[0][/[\w\s\'&]+/].gsub(/\'/, '').gsub(/&/, ' and ')
        end

    CategoryRegexpTbl = CategoryRssTbl.map do |c|
        Regexp.new(c[0][/^[\w]+/])
    end


    #
    # get category index for feed
    #
    def self.getCategoryIndex(categories)
        cats = categories.split(/,/)
        cats.find do |ca|
            CategoryRegexpTbl.each_with_index do |c, i|
                return i if c =~ ca
            end
        end
        -1
    end

    #
    # get feed address by category index
    #
    def self.getFeedAdrByCategoryIndex(catIndex)
        categoryStr = 'categories/' + BBCNet::CategoryRssTbl[ catIndex ][1] + '/radio'
        "http://feeds.bbc.co.uk/iplayer/#{categoryStr}/list"
    end

    #
    #
    #
    def self.getRssByCategoryIndex(catIndex, onRead)
        feedAdr = getFeedAdrByCategoryIndex(catIndex)
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }
        CachedRssIO.read(feedAdr, onRead)
    end
end

module AudioFile
    # return seconds of audio file duration.
    def self.getDuration(file)
        return 0 unless File.exist?(file)

        case file[/\.\w+$/].downcase
        when ".mp3"
            cmd = "| exiftool -S -Duration %s" % file.shellescape
        when ".wma"
            cmd = "| exiftool -S -PlayDuration %s" % file.shellescape
        end
        msg = open(cmd) do |f| f.read end
        a = msg.scan(/(?:(\d+):){0,2}(\d+)/)[0]
        return 0 unless a
        i = -1
        a.reverse.inject(0) do |s, d|
            i += 1
            s + d.to_i * [ 1, 60, 3600 ][i]
        end
    end
end



if __FILE__ == $0 then
#     puts AudioFile::getDuration(ARGV.shift)
#     exit 0

    class LogOut
        def write(msg)
            puts msg
        end
    end
    $app = Qt::CoreApplication.new(ARGV)

    def onReadMetaInfo(minfo)
        puts minfo.title

        minfo.streams.each do |s|
            puts "url : " + s.url
        end
        exit
    end

    $log = MyLogger.new(LogOut.new)
    pid = "b007jynb"
    if ARGV.size > 0 then
        pid = ARGV.shift
    end
    minfo = BBCNet::MetaInfo.new(pid)
    minfo.update(self.method(:onReadMetaInfo))

    $app.exec
end
