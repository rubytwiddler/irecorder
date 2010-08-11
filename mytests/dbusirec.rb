require 'uri'
require 'net/http'
require 'open-uri'
require 'ftools'
require 'rss'

require 'Qt'

require "bbcnet"

module NetRead
    SERVICE_NAME = 'com.rubyscripts.irecorder'
    READ_PATH = '/netread'

    
    class Reader < Qt::Object
        slots   'QByteArray read(const QString&)'
        slots   'quit()'

        def read(url)
            rss = RSS::Parser.parse( BBCNet.read(url) )
            Qt::ByteArray.new(Marshal.dump(rss))
        end

        def quit
            Qt::CoreApplication.instance.quit
            "bye"
        end

    end

    def dbus_cleanup
        iface = Qt::DBusInterface.new(SERVICE_NAME, READ_PATH, "", Qt::DBusConnection.sessionBus)
        raise "D-BUS Interface Error : #{Qt::DBusConnection.sessionBus.lastError.message}" unless iface.valid?
        msg = iface.call("quit")
#         reply = Qt::DBusReply.new(msg)
    end

    
    def dbus_initialize(parent)
        if !Qt::DBusConnection::sessionBus.connected?
            raise 'D-Bus Error. D-Bus system is not running.'
        end
        iface = Qt::DBusInterface.new(SERVICE_NAME, READ_PATH, "", Qt::DBusConnection.sessionBus)
        unless iface.valid?
            puts "start process DBUS in background."
            process = Qt::Process.new(parent)
            process.start('/usr/bin/ruby', [__FILE__])
        end
    end

    # server side initialization.
    def start_service
        if !Qt::DBusConnection.sessionBus.registerService(SERVICE_NAME)
            raise "D-Bus Error : #{Qt::DBusConnection.sessionBus.lastError.message}"
        end

        reader = Reader.new
        Qt::DBusConnection.sessionBus.registerObject(READ_PATH, reader, Qt::DBusConnection::ExportAllSlots)
    end

    # client side call. blocked call
    def read
        iface = Qt::DBusInterface.new(SERVICE_NAME, READ_PATH, "", Qt::DBusConnection.sessionBus)
        raise "D-BUS Interface Error : #{Qt::DBusConnection.sessionBus.lastError.message}" unless iface.valid?
        msg = iface.call(Qt::DBus::BlockWithGui, "read", url)
        reply = Qt::DBusReply.new(msg)
        raise "D-BUS Reply Error : #{reply.error.message}" unless reply.valid?
        reply.value
    end

    # client side call. with callback
    def readRequest(url, obj, returnMethod, errMethod)
        iface = Qt::DBusInterface.new(SERVICE_NAME, READ_PATH, "", Qt::DBusConnection.sessionBus)
        raise "D-BUS Interface Error : #{Qt::DBusConnection.sessionBus.lastError.message}" unless iface.valid?
        
        f = iface.callWithCallback("read", [url], obj, returnMethod, errMethod)
        raise "D-BUS Call Error : #{Qt::DBusConnection.sessionBus.lastError.message}" unless f
        "request url : '#{url}'"
    end
end

include NetRead

if __FILE__ == $0
    app = Qt::CoreApplication.new(ARGV)
    NetRead::start_service
    app.exec
end
    