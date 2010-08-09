#
#
#
require 'rubygems'
require 'uri'
require 'net/http'
require 'open-uri'
require 'rss'
require 'nokogiri'
require 'shellwords'
require 'fileutils'

UrlRegexp = URI.regexp(['rtsp','http'])

#
# use services on net
#  http://linuxcentre.net, http://iplayerconverter.co.uk
#
class BBCNet
    RtspRegexp = URI.regexp(['rtsp'])
    MmsRegexp = URI.regexp(['mms'])
    DirectStreamRegexp = URI.regexp(['mms', 'rtsp', 'rtmp', 'rtmpt'])




    # class Info
    #  construct information from http://linuxcentre.net service.
    #
    class Info
        def initialize
        end

        def normalizeKey(rawKey)
            case rawKey
            when / aac +48/i
                "aacLow"
            when / aac +128/i
                "aacStd"
            when / mp3/i
                "mp3"
            when / wma +128/i
                "wma"
            when /\bduration\b/i
                "duration"
            when /programme +id/i
                "pid"
            else
                ss = rawKey.gsub(/[\[\(].*?[\]\)]/, '').gsub(/[^\w ]/, '_').split(/ /)
                head = ss.shift.downcase
                ss = [ head ] + ss.map do |s| s.capitalize end
                ss.join
            end
        end

        def add(rawKey, value)
            key = normalizeKey(rawKey)
            sym = '@' + key
            instance_variable_set(sym, value)
            if self.class.method_defined? key then
                self.class.class_eval %Q{
                    def #{key}
                        #{sym}
                    end
                }
            end
        end

        StreamNames = ['wma', 'mp3', 'aacStd', 'aacLow']
        def streamTempUrl(pref=StreamNames)
            pref = pref - (pref - StreamNames)
            pref.find do |k|
                k = '@' + k
                if self.instance_variable_defined?(k)
                    url = self.instance_variable_get(k)
                    return url if url
                end
                false
            end
            nil
        end

        def streamDirectUrl(pref=StreamNames)
            url = streamTempUrl(pref)
            puts "in streamDirectUrl : url = " + url.inspect
            BBCNet.getDirectStreamUrl(url)
        end
    end

    # http://linuxcentre.net/iplayersearch?DATAONLY=1&NEXTPAGE=show_info&INFO=radio|b00hs6lj
    # return informatin Hash
    def self.getInfo(pid)
        # use Net::HTTP method to avoid uri Error which is caused by '|' char
        #  instead of open-uri.
#         res = Net::HTTP.start("linuxcentre.net") do |http|
#             http.get("/iplayersearch?DATAONLY=1&NEXTPAGE=show_info&INFO=radio|#{pid}")
#         end .body
        res = IO.read("../tmp/iplayer-ajax-02.xml")

        doc = Nokogiri::HTML(res)
        node = doc.at_css("table")

        info = Info.new
        tbls = node.css("dt")
        tbls.each do |row|
            key = row.content.to_s
            value = row.next.content.to_s
            info.add(key, value)
        end

        info
    end

    #------------------------------------------------------------------------
    # get stream metadata
    # episode url => pid => xml playlist => version pid (vpid aka. identifier) => xml stream metadata => wma
    #
    class MetaInfo
        def self.get(url)
            pid = self.extractPid(url)
#             info = @cachePid[pid]
#             return info if info
            self.new(pid)
        end

        attr_reader :pid
        Keys = [ :duration, :vpid, :group, :media, :onAirDate, :channel, :title, :summary, :aacLow, :aacStd, :mp3, :wma, :streams ]
        def initialize(pid)
            @pid = pid
            Keys.each do |k|
                s = ('@' + k.to_s).to_sym
                self.instance_variable_set(s, nil)
                self.class.class_eval %Q{
                    def #{k}
                        #{s}
                    end
                }
            end

            @streams = []
        end


        #
        # read duration, vpid, group, media, onAirDate, channel
        #   from XmlPlaylist
        def readXmlPlaylist
            return self if @vpid

            res = BBCNet.read("http://www.bbc.co.uk/iplayer/playlist/#{@pid}")
#             res = IO.read("../tmp/iplayer-playlist-me.xml")

            doc = Nokogiri::XML(res)
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


        class StreamInfo
            #  example)    48, wma, time, audio, http://..
            attr_accessor :bitrate, :encoding, :expires, :type, :indirectUrl
            alias       :kind :type

            def url
                return @url if @url
                @url = BBCNet.getDirectStreamUrl(@indirectUrl)
            end
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
                stmInf.expires = BBCNet.getTime(m[:expires])    #
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
                end
            end
            self
        end

    end



    def self.getTime(str)
        tm = str.match(/(\d{4})-(\d\d)-(\d\d)\w(\d\d):(\d\d):(\d\d)/)
        par = ((1..6).inject([]) do |a, n| a << tm[n].to_i end)
        Time.gm( *par )
    end

    #------------------------------------------------------------------------
    #
    #

    # convert epsode Url to console Url
    # example
    #  from
    #    http://www.bbc.co.uk/iplayer/episode/b007jpkt/Miss_Marple_A_Caribbean_Mystery_Episode_1/
    #  to
    #    http://www.bbc.co.uk/iplayer/console/b007jpkt
    def self.getPlayerConsoleUrl(url)
        uri = URI.parse(url)
        spath = uri.path.split('/')

        raise 'Missing IPlayer path' unless spath[1] == 'iplayer'

        newpath = '/iplayer/console/' + spath[3]
        uri.path = newpath
        uri.to_s
    end

    # get PID from BBC episode Url
    def self.extractPid(url)
        case url
        when %r!/(?:item|episode|programmes)/([a-z0-9]{8})!
            $1
        when %r!^[a-z0-9]{8}$!
            url
        when %r!\b(b0[a-z0-9]{7}\b)!
            $1
        else
            raise "No PID in Url '%s'" % url
        end
    end


#     # extract console HTML body and extract .ram urls
#     # example
#     #  from
#     #    http://www.bbc.co.uk/iplayer/console/b007jpkt
#     #  to
#     #    http://www.bbc.co.uk/iplayer/aod/playlists/9n/29/20/0b/RadioBridge_intl_1900_bbc_7.ram
#     def self.getRamUrlFromIPlayerConsole(url)
# #         res = Net::HTTP.get(URI.parse(url))
#         res = self.read(url)
#         res.scan( UrlRegexp ).find_all do |u|
#                 u[3] =~ /bbc/ && u[6] =~ /\.ram$/
#             end .map do |a|
#                 a[0] + '://' + a[3] + a[6]
#             end .uniq
#     end
#
#     # get raw file urls from episode Url
#     def self.getRawUrls(url)
#         uri = URI.parse(url)
#         spath = uri.path.split('/')
#
#         raise 'Missing IPlayer path' unless spath[1] == 'iplayer'
#
#         self.getRawUrlsFromPid(spath[3])
#     end
#
#     def self.getRawUrlsFromIPlayerConsole(url)
#         pid = url.sub(%r{.*/}, '')
#         self.getRawUrlsFromPid(pid)
#     end
#
#     # get Wma file url from episode url
#     def self.getWmaFromUrl(url)
#         urls = BBCNet.getRawUrls(url)
#         url = urls['wma']
#         raise 'no wma file' if !url or url.empty?
#         BBCNet.getRawFileUrlfromAsf(url)
#     end
#
#     # convert read or wmv url from console url
#     # example
#     #  from
#     #    http://www.bbc.co.uk/iplayer/console/b00mf04l
#     #  to
#     #    real=http://www.bbc.co.uk/mediaselector/4/mtis/stream/b00mf026
#     #    ra=
#     #    wma=http://www.bbc.co.uk/radio/listen/again/b00mf026.asx
#     #
#     def self.getRawUrlsFromPid(pid)
#         cnvUrl = "http://www.iplayerconverter.co.uk/pid/#{pid}/default.aspx"
#         doc = nil
#         open(cnvUrl) do |f|
#             doc = Nokogiri::HTML(f)
#         end
#
#         node = doc.at_css("body")
#         node.css("script").remove
#
#         fileUrls = Hash.new
#         node.content .to_s. split(/,/).each do |a|
#             k,v = a.strip.split(/=/, 2)
#             fileUrls[k] = v
#         end
#
#         fileUrls
#     end
#
#     # extract .ra url from .ram url
#     # example
#     #  toRawFileUrlfromRam('http://bbc.co.uk/path/music.ram')  #=> 'http://bbc.co.uk/direct_path_in_ra/music.ra
#     #
#     def self.getRawFileUrlfromRam(url)
#         if url !~ RtspRegexp then
#            # .ram => .ra
#             res = self.read(url)
#             newSrc= res[ RtspRegexp ]  # 1st
#             if newSrc.nil? then
#                 raise 'Cannot get RA url from RAM url'
#             else
#                 url = newSrc
#             end
#         end
#         url
#     end
#
#     # extract .wma url from .asf url
#     # example
#     #  toRawFileUrlfromAsf('http://www.bbc.co.uk/radio/listen/again/b00t5jf6.asx')  #=> 'mms://wm.bbc.co.uk/wms/bbc7coyopa/bbc7_-_saturday_1700.wma'
#     #
#     def self.getRawFileUrlfromAsf(url)
#         if url !~ MmsRegexp then
#            # .asf => .wma
#             res = self.read(url)
#             newSrc= res[ MmsRegexp ]  # 1st
#             if newSrc.nil? then
#                 raise 'Cannot get Wma url from Asf url'
#             else
#                 url = newSrc
#             end
#         end
#         url
#     end

    # .asf/.ram => .wma/.ra
    def self.getDirectStreamUrl(url)
        unless url[DirectStreamRegexp] then
#             puts " get direct url of " + url
            res = self.read(url)
            newSrc= res[ DirectStreamRegexp ]
            url = newSrc unless newSrc.nil?
        end
        url
    end


    def self.read(url)
        header = { "User-Agent" => self.randomUserAgent }
        if defined? @@proxy
            header[:proxy] = @@proxy
        end

        uri = URI.parse(url)
        res = Net::HTTP.start(uri.host, uri.port) do |http|
            http.get(uri.path, header)
        end
        res.body
    end

    def self.setProxy(url)
        @@proxy = url
    end

    private
    UserAgentList = [
        'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/<RAND>.8 (KHTML, like Gecko) Chrome/2.0.178.0 Safari/<RAND>.8',
        'Mozilla/5.0 (compatible; MSIE 7.0; Windows NT 6.0; SLCC1; .NET CLR 2.0.50<RAND>; Media Center PC 5.0; c .NET CLR 3.0.0<RAND>6; .NET CLR 3.5.30<RAND>; InfoPath.1; el-GR)',
        'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 2.0.50<RAND>; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30<RAND>; InfoPath.1)',
        'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0; YPC 3.2.0; SLCC1; .NET CLR 2.0.50<RAND>; .NET CLR 3.0.04<RAND>)',
        'Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_4_11; tr) AppleWebKit/<RAND>.4+ (KHTML, like Gecko) Version/4.0dp1 Safari/<RAND>.11.2',
        'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50<RAND>; .NET CLR 3.5.30<RAND>; .NET CLR 3.0.30<RAND>; Media Center PC 6.0; InfoPath.2; MS-RTC LM 8)',
        'Mozilla/6.0 (Windows; U; Windows NT 7.0; en-US; rv:1.9.0.8) Gecko/2009032609 Firefox/3.0.9 (.NET CLR 3.5.30<RAND>)',
        ]
    def self.randomUserAgent
        ua = UserAgentList[ rand UserAgentList.length ]
        ua.gsub(/<RAND>/, "%03d" % rand(1000))
    end

end

module AudioFile
    # return seconds of audio file duration.
    def getDuration(file)
        case file[/\.\w+$/].downcase
        when ".mp3"
            cmd = "| exiftool -S -Duration %s" % file.shellescape
        when ".wma"
            cmd = "| exiftool -S -PlayDuration %s" % file.shellescape
        end
        msg = open(cmd) do |f| f.read end
        a = msg.scan(/(?:(\d+):){0,2}(\d+)/)[0]
        i = -1
        a.reverse.inject(0) do |s, d|
            i += 1
            s + d.to_i * [ 1, 60, 3600 ][i]
        end
    end
end

include AudioFile


if __FILE__ == $0 then
    pid = "b00mzvfq"
    if ARGV.size > 0 then
        pid = ARGV.shift
    end
#     info = BBCNet.getInfo(pid)
#     puts info.inspect
#     puts "duration : " + info.duration
#     puts "mp3 : " + info.streamDirectUrl(['mp3'])
    minfo = BBCNet::MetaInfo.new(pid)
    minfo.readXmlStreamMeta
    puts minfo.inspect

    minfo.streams.each do |s|
        puts "url : " + s.url
    end

    oldMethodUrl = BBCNet.getRawUrlsFromPid(pid)
    puts "old method url : " + oldMethodUrl.inspect

    puts "  old wma url : " + BBCNet.getDirectStreamUrl( oldMethodUrl['wma'] )
end
