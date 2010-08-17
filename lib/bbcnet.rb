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
require 'tmpdir'
require 'singleton'

# my libs
require "cache"

UrlRegexp = URI.regexp(['rtsp','http'])

#
#
class BBCNet
    RtspRegexp = URI.regexp(['rtsp'])
    MmsRegexp = URI.regexp(['mms'])
    DirectStreamRegexp = URI.regexp(['mms', 'rtsp', 'rtmp', 'rtmpt'])

    class CacheMetaInfoDevice < CasheDevice::CacheDeviceBase
        def initialize(expireDuration = 6*60, cacheMax=200)
            super(expireDuration, cacheMax)
        end

        # return : [ data, key ]
        #  key : key to restore data.
        def directRead(pid)
            data = BBCNet::MetaInfo.new(pid).update
            [ data, data ]
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
#             info = @@cachePid[pid]
#             return info if info
            self.new(pid)
        end

        attr_reader :pid
        Keys = [ :duration, :vpid, :group, :media, :onAirDate, :channel, :title, :summary, :aacLow, :aacStd, :real, :wma, :streams ]
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
                @url ||= BBCNet.getDirectStreamUrl(@indirectUrl)
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
            end
            self
        end

        alias :update :readXmlStreamMeta

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


    # .asf/.ram => .wma/.ra
    def self.getDirectStreamUrl(url)
        old = ''
        while url != old and not url[DirectStreamRegexp] do
            old = url
            res = self.read(url)
            url = res[ DirectStreamRegexp ] or res[ UrlRegexp ] or old
            url ||= old         # ??? why need this ? ruby's bug ?
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
    def self.getDuration(file)
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



if __FILE__ == $0 then
    puts AudioFile::getDuration(ARGV.shift)
    exit 0

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
