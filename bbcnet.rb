#
#
#
require 'rubygems'
require 'nokogiri'

UrlRegexp = URI.regexp(['rtsp','http'])

class BBCNet
    RtspRegexp = URI.regexp(['rtsp'])
    MmsRegexp = URI.regexp(['mms'])



    # convert Ulr from epsode Url
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

    # extract console HTML body and extract .ram urls
    # example
    #  from
    #    http://www.bbc.co.uk/iplayer/console/b007jpkt
    #  to
    #    http://www.bbc.co.uk/iplayer/aod/playlists/9n/29/20/0b/RadioBridge_intl_1900_bbc_7.ram
    def self.getRamUrlFromIPlayerConsole(url)
#         res = Net::HTTP.get(URI.parse(url))
        res = self.read(url)
        res.scan( UrlRegexp ).find_all do |u|
                u[3] =~ /bbc/ && u[6] =~ /\.ram$/
            end .map do |a|
                a[0] + '://' + a[3] + a[6]
            end .uniq
    end

    # get raw file urls from episode Url
    def self.getRawUrls(url)
        uri = URI.parse(url)
        spath = uri.path.split('/')

        raise 'Missing IPlayer path' unless spath[1] == 'iplayer'

        self.getRawUrlsFromPid(spath[3])
    end

    def self.getRawUrlsFromIPlayerConsole(url)
        pid = url.sub(%r{.*/}, '')
        self.getRawUrlsFromPid(pid)
    end

    # get Wma file url from episode url
    def self.getWmaFromUrl(url)
        urls = BBCNet.getRawUrls(url)
        url = urls['wma']
        raise 'no wma file' if !url or url.empty?
        BBCNet.getRawFileUrlfromAsf(url)
    end

    # convert read or wmv url from console url
    # example
    #  from
    #    http://www.bbc.co.uk/iplayer/console/b00mf04l
    #  to
    #    real=http://www.bbc.co.uk/mediaselector/4/mtis/stream/b00mf026
    #    ra=
    #    wma=http://www.bbc.co.uk/radio/listen/again/b00mf026.asx
    #
    def self.getRawUrlsFromPid(pid)
        cnvUrl = "http://www.iplayerconverter.co.uk/pid/#{pid}/default.aspx"
        doc = nil
        open(cnvUrl) do |f|
            doc = Nokogiri::HTML(f)
        end

        node = doc.at_css("body")
        node.css("script").remove

        fileUrls = Hash.new
        node.content .to_s. split(/,/).each do |a|
            k,v = a.strip.split(/=/, 2)
            fileUrls[k] = v
        end

        fileUrls
    end

    # extract .ra url from .ram url
    # example
    #  toRawFileUrlfromRam('http://bbc.co.uk/path/music.ram')  #=> 'http://bbc.co.uk/direct_path_in_ra/music.ra
    #
    def self.getRawFileUrlfromRam(url)
        if url !~ RtspRegexp then
           # .ram => .ra
            res = self.read(url)
            newSrc= res[ RtspRegexp ]  # 1st
            if newSrc.nil? then
                raise 'Cannot get RA url from RAM url'
            else
                url = newSrc
            end
        end
        url
    end

    # extract .wma url from .ram url
    # example
    #  toRawFileUrlfromAsf('http://www.bbc.co.uk/radio/listen/again/b00t5jf6.asx')  #=> 'mms://wm.bbc.co.uk/wms/bbc7coyopa/bbc7_-_saturday_1700.wma'
    #
    def self.getRawFileUrlfromAsf(url)
        if url !~ MmsRegexp then
           # .asf => .wma
            res = self.read(url)
            newSrc= res[ MmsRegexp ]  # 1st
            if newSrc.nil? then
                raise 'Cannot get Wma url from Asf url'
            else
                url = newSrc
            end
        end
        url
    end

    def self.read(url)
        res = nil
        header = { "User-Agent" => self.randomUserAgent }
        if defined? @@proxy
            header[:proxy] = @@proxy
        end
        open(url, header) do |f|
            res = f.read
        end
        res
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
