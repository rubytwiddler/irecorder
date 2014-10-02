# encoding: utf-8
#
#
module CachedIO
    class CachedIOBase
        include Singleton

        class CachedData
            attr_accessor :expireTime, :url, :key
        end

        attr_accessor :cacheDuration, :cacheMax
        def initialize(cacheDuration = 26*60, cacheMax=10)
            @cacheDuration = cacheDuration
            @cache = Hash.new
            @cacheLRU = []          # Least Recently Used
            @cacheMax = cacheMax
        end

        #
        #
        def self.read(url)
            self.instance.read(url)
        end
        
        def read(url)
            startTime = Time.now
            cachedt = @cache[url]
            if cachedt and cachedt.expireTime > startTime then
                @cacheLRU.delete(cachedt)
                @cacheLRU.push(cachedt)
                data = restoreCache(cachedt.key)
                $log.debug { "cachedt %s: Time %f sec" %
                            [self.class.name, (Time.now - startTime).to_f] }
                return data
            end
            if @cacheLRU.size >= @cacheMax then
                oldest = @cacheLRU.shift
                @cache.delete(oldest)
            end
            cachedt = CachedData.new
            cachedt.url = url
            cachedt.expireTime = startTime + @cacheDuration
            data, cachedt.key = directRead(url)
            saveCache(cachedt.key, data)
            @cache[url] = cachedt
            @cacheLRU.push(cachedt)
            $log.debug {"direct read %s: Time %f sec" %
                        [self.class.name, (Time.now - startTime).to_f] }
            data
        end


        # @return : data
        #   restore data from key.
        def restoreCache(key)
            key
        end

        def saveCache(id, data)
        end

        # @return : data, key
        #  key : key to restore data.
        def directRead(url)
            raise "Implement directRead method."
        end
    end
end


#
#   practical implementations.
#


class CachedHttpDiskIO < CachedIO::CachedIOBase
    def initialize(cacheDuration = 12*60, cacheMax=50)
        super(cacheDuration, cacheMax)
        @tmpdir = Dir.tmpdir + '/bbc_cache'
        FileUtils.mkdir_p(@tmpdir)
    end

#     # @return : data
#     #   restore data from key.
#     def restoreCache(key)
#         IO.read(key)
#     end
# 
#     def saveCache(id, data)
#         IO.write(id, data)
#     end
    
    # @return : [ data, key ]
    #  key : key to restore data.
    def directRead(url)
        $log.misc { "directRead(): " + self.class.name }
        tmpfname = tempFileName(url)

        if File.exist?(tmpfname) then
            $log.misc { "File ctime  : " + File.ctime(tmpfname).to_s}
            $log.misc { "expire time : " + (File.ctime(tmpfname) + @cacheDuration).to_s }
            $log.misc { "Now Time    : " + Time.now.to_s }
        end

        if File.exist?(tmpfname) and
                File.ctime(tmpfname) + @cacheDuration > Time.now then
            data = IO.read(tmpfname)
        else
            data = BBCNet.read(url)
            open(tmpfname, "w") do |f| f.write(data) end
        end
        [ data, tmpfname ]
    end

    def tempFileName(url)
        File.join(@tmpdir, url.scan(%r{(?:iplayer/)[\w\/]+$}).first.gsub!(/iplayer\//,'').gsub!(%r|/|, '_'))
    end
end

class CachedObjectDiskIO < CachedIO::CachedIOBase
    def initialize(cacheDuration = 12*60, cacheMax=50)
        super(cacheDuration, cacheMax)
        @tmpdir = Dir.tmpdir + '/bbc_cache'
        FileUtils.mkdir_p(@tmpdir)
    end


    # @return : data
    #   restore data from id.
    def restoreCache(id)
        path = tempFileName(id)
        Marshal.load(IO.read(path))
    end

    def saveCache(id, data)
        path = tempFileName(id)
        open(path, "w") do |f|
            f.write(Marshal.dump(data))
        end
    end

    # @return : [ data, key ]
    #  key : key to restore data.
    def directRead(url)
        $log.misc { "directRead(): " + self.class.name }
        tmpfname = tempFileName(url)

        if File.exist?(tmpfname) then
            $log.misc { "File ctime  : " + File.ctime(tmpfname).to_s}
            $log.misc { "expire time : " + (File.ctime(tmpfname) + @cacheDuration).to_s }
            $log.misc { "Now Time    : " + Time.now.to_s }
        end

        if File.exist?(tmpfname) and
                File.ctime(tmpfname) + @cacheDuration > Time.now then
            data = IO.read(tmpfname)
        else
            data = BBCNet.read(url)
            open(tmpfname, "w") do |f| f.write(data) end
        end
        [ data, tmpfname ]
    end

    def tempFileName(url)
        File.join(@tmpdir, url.gsub(%r|[^\w]|, '_'))
    end
end

class CachedRssIO < CachedIO::CachedIOBase
    def initialize(cacheDuration = 12*60, cacheMax=6)
        super(cacheDuration, cacheMax)
    end

    # @return : [ data, key ]
    #  key : key to restore data.
    def directRead(url)
         data = Nokogiri::XML(CachedHttpDiskIO.read(url))
         [ data, data ]
    end
end
