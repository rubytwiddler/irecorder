#
#
#
module CachedIO
    #
    # CacheReply class
    #
    class CacheReply < Qt::Object
        def initialize(url, onRead)
            super()
            @url = url
            @onRead = onRead
            @startTime = Time.now
        end

        def call(*arg)
            @onRead.call(*arg)
            deleteLater
        end

        attr_accessor :url, :id, :data, :obj, :onFinish
        attr_reader :startTime

        # @return this object's finished method(name is atEnt)
        #  chain this returned method for other onRead with object.
        # e.g :
        #   OtherRead(url, cacheReply.finishedMethod(self.method(:mainOnRead))
        # end
        #
        # def mainOnRead(reply)
        #   ..
        def finishedMethod(onFinish)
            @onFinish = onFinish
            self.method(:atEnd)
        end

        protected
        def atEnd(data)
            @data = @id = data
            @onFinish.call(self)
            deleteLater
        end
    end

    #
    # CachedIOBase class
    #
    class CachedIOBase < Qt::Object
        include Singleton


        #
        # CachedData class
        #
        class CachedData
            # id is raw data or id to restore data.
            attr_accessor :expireTime, :url, :id
        end

        #---------------------------------------
        #
        #   CachedIOBase class
        #
        attr_accessor :cacheDuration, :cacheMax
        def initialize(cacheDuration = 26*60, cacheMax=10)
            super()
            @cacheDuration = cacheDuration
            @cache = Hash.new
            @cacheLRU = []          # Least Recently Used
            @cacheMax = cacheMax
        end

        #
        #
        def self.read(url, onRead)
            self.instance.read(url, onRead)
        end

        #
        #
        #
        def read(url, onRead)
            startTime = Time.now
            cachedt = @cache[url]
            if cachedt and cachedt.expireTime > startTime then
                @cacheLRU.delete(cachedt)
                @cacheLRU.push(cachedt)
                data = restoreCache(cachedt.id)
                $log.debug { "cache %s: Time %f sec" %
                            [self.class.name, (Time.now - startTime).to_f] }
                onRead.call(data)
                return
            end
            if @cacheLRU.size >= @cacheMax then
                oldest = @cacheLRU.shift
                @cache.delete(oldest)
            end
            directRead(url, onRead)
        end

        protected
        # @return : data
        #   restore data from id.
        def restoreCache(id)
            id
        end

        # @param url : query url
        # @param onRead : method called when all process is finished.
        # method finished(reply) will be called when read is finished.
        def directRead(url, onRead)
            raise "Implement directRead method."
            reply = CacheReply.new(url, onRead)
            reply.data = reply.id = "data"
            finished(reply)
        end

        def finished(reply)
            startTime = reply.startTime
            cachedt = CachedData.new
            cachedt.url = url = reply.url
            cachedt.id = reply.id
            cachedt.expireTime = startTime + @cacheDuration

            @cache[url] = cachedt
            @cacheLRU.push(cachedt)
            $log.debug {"direct read %s: Time %f sec" %
                        [self.class.name, (Time.now - startTime).to_f] }
            reply.call(reply.data)
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
        @manager = Qt::NetworkAccessManager.new(self)
        connect(@manager, SIGNAL('finished(QNetworkReply*)'), self, \
                SLOT('rawFinished(QNetworkReply*)'))
    end


    # @return : data
    #   restore data from key.
    def restoreCache(key)
        IO.read(key)
    end

    # method finished(reply) will be called when read is finished.
    def directRead(url, onRead)
        $log.misc { "directRead(): " + self.class.name }
        tmpfname = tempFileName(url)

        if File.exist?(tmpfname) then
            $log.misc { "File ctime  : " + File.ctime(tmpfname).to_s}
            $log.misc { "expire time : " + (File.ctime(tmpfname) + @cacheDuration).to_s }
            $log.misc { "Now Time    : " + Time.now.to_s }
        end

        reply = CachedIO::CacheReply.new(tmpfname, onRead)
        reply.id = tmpfname
        reply.url = url
        if File.exist?(tmpfname) and
                File.ctime(tmpfname) + @cacheDuration > Time.now then
            data = IO.read(tmpfname)
        else
            request = Qt::NetworkRequest.new(Qt::Url.new(url))
            request.setOriginatingObject(reply)
            @manager.get(request)
            return
        end
        reply.data = data
        finished(reply)
    end

    slots 'rawFinished(QNetworkReply*)'
    def rawFinished(netReply)
        reply = netReply.request.originatingObject
        reply.data = netReply.readAll.data
        open(reply.id, "w") do |f| f.write(reply.data) end
        finished(reply)
    end

    def tempFileName(url)
        File.join(@tmpdir, url.scan(%r{(?:iplayer/)[\w\/]+$}).first.gsub!(/iplayer\//,'').gsub!(%r|/|, '_'))
    end
end

class CachedRssIO < CachedIO::CachedIOBase
    def initialize(cacheDuration = 12*60, cacheMax=6)
        super(cacheDuration, cacheMax)
    end

    # method finished(reply) will be called when read is finished.
    def directRead(url, onRead)
        reply = CachedIO::CacheReply.new(url, onRead)
        CachedHttpDiskIO.read(url, reply.finishedMethod(self.method(:rawFinished)))
    end

    def rawFinished(reply)
        data = Nokogiri::XML(reply.data)
        reply.data = data
        finished(reply)
    end
end


