#
#
#
module CasheDevice
    class CacheDeviceBase
        include Singleton

        class CachedData
            attr_accessor :expireTime, :url, :key
        end

        attr_accessor :cacheDuration, :cacheMax
        def initialize(cacheDuration = 26*60, cacheMax=10)
            @cacheDuration = cacheDuration      # 12 minutes
            @cache = Hash.new
            @cacheLRU = []          # Least Recently Used
            @cacheMax = cacheMax
        end

        # return : data, key
        #  key : key to restore data.
         def directRead(url)
             raise "Implement directRead method."
         end

        # return : data
        #   restore data from key.
        def restoreCache(key)
            key
        end

        def read(url)
            startTime = Time.now
            cached = @cache[url]
            if cached and cached.expireTime > startTime then
                @cacheLRU.delete(cached)
                @cacheLRU.push(cached)
                data = restoreCache(cached.key)
                $log.debug { "cached %s: Time %f sec" %
                            [self.class.name, (Time.now - startTime).to_f] }
                return data
            end
            if @cacheLRU.size >= @cacheMax then
                oldest = @cacheLRU.shift
                @cache.delete(oldest)
            end
            cached = CachedData.new
            cached.url = url
            cached.expireTime = startTime + @cacheDuration
            data, cached.key = directRead(url)
            @cache[url] = cached
            @cacheLRU.push(cached)
            $log.debug {"direct read %s: Time %f sec" %
                        [self.class.name, (Time.now - startTime).to_f] }
            data
        end


        def self.read(url)
            self.instance.read(url)
        end
    end
end


#
#   practical implementations.
#
class CacheRssDevice < CasheDevice::CacheDeviceBase
    def initialize(cacheDuration = 12*60, cacheMax=6)
        super(cacheDuration, cacheMax)
    end

    # return : [ data, key ]
    #  key : key to restore data.
    def directRead(url)
         data = RSS::Parser.parse(CacheHttpDiskDevice.read(url))
         [ data, data ]
    end
end


class CacheHttpDiskDevice < CasheDevice::CacheDeviceBase
    def initialize(cacheDuration = 12*60, cacheMax=30)
        super(cacheDuration, cacheMax)
        @tmpdir = Dir.tmpdir + '/bbc_cache'
        FileUtils.mkdir_p(@tmpdir)
    end

    # return : data
    #   restore data from key.
    def restoreCache(key)
        IO.read(key)
    end

    # return : [ data, key ]
    #  key : key to restore data.
    def directRead(url)
        puts "directRead(): " + self.class.name
        tmpfname = tempFileName(url)

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
        File.join(@tmpdir, url.scan(%r{\w+/\w+$}).first.gsub(%r|/|, '_'))
    end
end
