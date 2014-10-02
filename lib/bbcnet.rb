# encoding: utf-8
#
#
require 'rubygems'
require 'uri'
require 'net/http'
require 'open-uri'
require 'nokogiri'
require 'shellwords'
require 'fileutils'
require 'tmpdir'
require 'singleton'
require 'yaml'
require 'date'
require 'Qt'

# my libs
require "cache"
require "logwin"

UrlRegexp = URI.regexp(['rtsp','http', 'mms'])

#
#
class BBCNet
    RtspRegexp = URI.regexp(['rtsp'])
    MmsRegexp = URI.regexp(['mms'])
    DirectStreamRegexp = URI.regexp(['mms', 'rtsp', 'rtmp', 'rtmpt'])

    
    class CachedMetaInfoIO < CachedObjectDiskIO
        # cacheMax is max of memory size, not max of files.
        def initialize(cacheDuration = 24*60*60, cacheMax=200)
            super(cacheDuration, cacheMax)
            @tmpdir = File.join(@tmpdir, 'meta_info')
            FileUtils.mkdir_p(@tmpdir)
        end

        # @return : [ data, key ]
        #  key : key to restore data.
        def directRead(pid)
            data = BBCNet::MetaInfo.new(pid).update
            [ data, pid ]
        end

        def self.read(url)
            pid = BBCNet.extractPid(url)
            self.instance.read(pid)
        end
    end

    #------------------------------------------------------------------------
    # get stream metadata
    # episode url => pid => xml playlist => version pid (vpid aka. identifier)
    #   => xml stream metadata => wma
    #
    class MetaInfo
        def self.get(url)
            pid = BBCNet.extractPid(url)
            self.new(pid)
        end

        attr_reader :pid
        Keys = [ :duration, :vpid, :group, :media, :onAirDate, :channel, :title, :summary, \
                 :aacLow, :aacStd, :real, :wma, :streams, :channelIndex ]
        attr_reader *Keys
        
        def initialize(pid)
            @pid = pid
            @streams = []
            @channelIndex = -1
        end

        # media [Radio,TV]
        def mediaName
            media.capitalize
        end

        # channel [BBC Radio 4, ..]
        alias :channelName :channel

        
        def cleanData
            remove_instance_variable :@onRead
            @aacLow = @aacLow.dup.cleanData if @aacLow
            @aacStd = @aacStd.dup.cleanData if @aacStd
            @real = @real.dup.cleanData if @real
            @wma = @wma.dup.cleanData if @wma
            @streams = @streams.map do |s| s.dup.cleanData end
            self
        end
        

        class StreamInfo
            #  example)    48, wma, time, audio, http://..
            attr_accessor :bitrate, :encoding, :expires, :type, :indirectUrl
            alias       :kind :type

            def url
                @url ||= BBCNet.getDirectStreamUrl(@indirectUrl)
            end
            
            def sizeRate
                940
            end
        end
        
        def streamInfo(prefered=%w{wma real aac aaclow})
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

        def readXmlStreamMeta
            readXmlPlaylist unless @vpid

            res = BBCNet.read("http://www.bbc.co.uk/mediaselector/4/mtis/stream/#{vpid}")
#             res = IO.read("../tmp/iplayer-stream-meta-me.xml")

            doc = Nokogiri::XML(res)
            me = doc.css("media")
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
                when /\bwma\d?\b/i
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
            end
            self
        end

        alias :update :readXmlStreamMeta

        protected
        #
        # read duration, vpid, group, media, onAirDate, channel
        #   from XmlPlaylist
        def readXmlPlaylist
            return self if @vpid

            res = BBCNet.read("http://www.bbc.co.uk/iplayer/playlist/#{@pid}")
#             res = IO.read("../tmp/iplayer-playlist-me.xml")
            $log.info{ [ "<< pid:#{@pid} playlist :", res, ":>>" ] }
            doc = Nokogiri::XML(res)
            item = doc.at_css("noItems")
            raise "No Playlist " + item[:reason] if item

            item = doc.at_css("item")
            @media = item[:kind].gsub(/programme/i, '')
            @duration = item[:duration].to_i
            @vpid = item[:identifier]
            @group = item[:group]
            @onAirDate = BBCNet.getTime(item.at_css("broadcast").content.to_s)
            @channel = item.at_css("service").content.to_s
            @title = item.at_css("title").content.to_s
            @summary = doc.at_css("summary").content.to_s
            self
        end

    end
    # end of MetaInfo class


    class ProgrammeInfo
        def initialize( *data )
            @title, @categories, updated, @content, @link = *data
            @tags = @categories.split(/,/)
            @catIndex = BBCNet::getCategoryIndex(@categories)
            @updated = BBCNet.getTime(updated)
            @url = @content[UrlRegexp]
            @genre = BBCNet.genreName(@tags)
            @minfo = nil
        end
        attr_reader :title, :categories, :catIndex, :updated, :content, :link, \
                :url, :tags, :genre, :minfo

        def cleanData
            @minfo = nil
            self
        end

        def readMetaInfo()
            if @minfo then
                $log.debug { "#{self.class.name}.readMetaInfo : @minfo:#{@minfo}" }
                return
            end
            minfo = CachedMetaInfoIO.read(@url)
            @minfo = minfo
        end
    end



    #------------------------------------------------------------------------
    #
    #  BBCNet class method
    #
    public
    def self.getTime(str)
        tm = str.match(/(\d{4})-(\d\d)-(\d\d)\w(\d\d):(\d\d):(\d\d)/)
        return Time.at(0) unless tm
        par = ((1..6).inject([]) do |a, n| a << tm[n].to_i end)
        Time.gm( *par )
    end

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


    public
    # .asf/.ram => .wma/.ra
    def self.getDirectStreamUrl(url)
        res = url
        old = nil
        while true do
            url = res[ DirectStreamRegexp ] || res[ UrlRegexp ] || old
            $log.misc { "new url:#{url},  old url:#{old}" }
            if url != old and not url[DirectStreamRegexp] then
                old = url
                res = BBCNet.read(url)
            elsif not url[ UrlRegexp ] then
                $log.info { "no url in response '#{res}'" }
                return "http://www.bbc.co.uk"+old
            else
                return url
            end
        end
    end


    def self.read(url)
        header = { "User-Agent" => self.randomUserAgent }
        if defined? @@proxy
            header[:proxy] = @@proxy
        end

        uri = URI.parse(url)
        res = Net::HTTP.start(uri.host, uri.port) do |http|
            http.get(uri.request_uri, header)
        end
        res.body
    end


    def self.setProxy(url)
        @@proxy = url
    end

    private
    UserAgentList = [
        'Mozilla/5.0 (Windows; U; Windows NT 7.0; en-US) AppleWebKit/<RAND>.13 (KHTML, like Gecko) Chrome/9.0.<RAND> Safari/<RAND>.1',
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

    RadioChannelShortNameTbl = %w{ radio1 1xtra radio2 radio3 radio4 5live 5livesportsextra 6music radio7 asiannetwork worldservice radioscotland radionangaidheal radioulster radiofoyle radiowales radiocymru }

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

    ChannelNameTbl = RadioChannelRssTbl.map do |c|
        c[0][/[\w\s\'&]+/].gsub(/\'/, '').gsub(/&/, ' and ')
    end

    ChannelRegexpTbl = RadioChannelRssTbl.map do |c|
        Regexp.new(c[0].gsub(/BBC /, ''), true)
    end

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
    # get Rss by category index
    #
    def self.getRssByCategoryIndex(catIndex)
        feedAdr = getFeedAdrByCategoryIndex(catIndex)
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }
        CachedRssIO.read(feedAdr)
    end



    #
    #   channel index access routines
    #

    #
    # get channel index for feed
    #
    def self.getChannelIndex(channelStr)
        ca = channelStr.chomp
        ChannelRegexpTbl.each_with_index do |c, i|
            return i if c =~ ca
        end
        -1
    end

    def self.getChannelStrByIndex(index)
        RadioChannelRssTbl[index][0]
    end

    #
    # get feed address by category index
    #
    def self.getFeedAdrByChannelIndex(channelIndex)
        channelStr = BBCNet::RadioChannelRssTbl[ channelIndex ][1]
        "http://feeds.bbc.co.uk/iplayer/#{channelStr}/list"
    end

    #
    # get Rss by category index
    #
    def self.getRssByChannelIndex(channelIndex)
        feedAdr = getFeedAdrByChannelIndex(channelIndex)
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }
        CachedRssIO.read(feedAdr)
    end

    class CachedScheduleHtmlIO < CachedHttpDiskIO
        def initialize(cacheDuration = 24*60*7, cacheMax=1)
            super
        end

        def tempFileName(url)
            File.join(@tmpdir, url.gsub(%r|^.*\.co\.uk/|, '').gsub(%r/[^\w]/, '_'))
        end
    end
    #
    def self.getScheduleAdrByWeekdayAndChannel(weekday, channelIndex)
        raise "out of range of weekday" unless (0..6).include?(weekday)
        day = Date.today
        day -= ((day.wday - weekday) % 7)
        dayStr = (channelIndex == 4 ? 'fm/': '') +day.strftime("20%y/%m/%d")
        channelStr = BBCNet::RadioChannelShortNameTbl[channelIndex]
#         "http://www.bbc.co.uk/radio7/programmes/schedules/2011/02/16"
        "http://www.bbc.co.uk/#{channelStr}/programmes/schedules/#{dayStr}"
    end

    def self.getScheduleHtmlByWeekdayAndChannel(weekday, channelIndex)
        feedAdr = getScheduleAdrByWeekdayAndChannel(weekday, channelIndex)
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }
        CachedScheduleHtmlIO.read(feedAdr)
    end

    #
    # Main Genre [Drama, Comedy, ..]
    #
    def self.genreName(tags)
        BBCNet::CategoryNameTbl.find do |cat|
            tags.find do |t|
                cat =~ /#{t}/i
            end
        end
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

    $log = MyLogger.new(STDOUT)
    pid = "b00mzvfq"
    if ARGV.size > 0 then
        pid = ARGV.shift
    end
    minfo = BBCNet::MetaInfo.new(pid)
    minfo.readXmlStreamMeta
    puts minfo.inspect

    minfo.streams.each do |s|
        puts "url : " + s.url
    end
end
