#!/usr/bin/ruby

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_VERSION = "0.1"

require 'korundum4'

class PassivePopup
    ServiceName = "org.kde.VisualNotifications"
    ServicePath = "/VisualNotifications"

    # client side call. blocked call
    def self.popup(msg)
        iface = Qt::DBusInterface.new(ServiceName, ServicePath, "", Qt::DBusConnection.sessionBus)
        raise "D-BUS Interface Error : #{Qt::DBusConnection.sessionBus.lastError.message}" unless iface.valid?
#         Qt.debug_level = Qt::DebugLevel::High
        args = []
        args << "irecorder"    # app_name
        args << 0              # replaces_id (uint)
        args << "irecorderPassivePopUp" # event_id
        args << "irecorder"    # app_icon
        args << "Warning!"     # summary
        args << msg            # body
        args << {}             # actions
        args << nil            # QVariantMap hints
        args << 8*1000         # time out

        msg = iface.callWithArgumentList(Qt::DBus::BlockWithGui, 'Notify', args)
        p msg
        reply = Qt::DBusReply.new(msg)
        raise "D-BUS Reply Error : #{reply.error.message}" unless reply.valid?
    end
end

class MainWindow < KDE::MainWindow
    def initialize
        super(nil)

        @type = 2

        # create widgets
        @text = Qt::TextEdit.new
        @text.plainText = "Hello World!"
        @btn = Qt::PushButton.new('Send') do |w|
            w.connect(SIGNAL(:clicked)) do
                case @type
                when 0
Qt.debug_level = Qt::DebugLevel::High
                PassivePopup::popup(@text.plainText)
Qt.debug_level = Qt::DebugLevel::Off
                when 1
                    %x{ kdialog --passivepopup '#{@text.plainText}' }
                when 2
                    @popup = KDE::PassivePopup::message(@text.plainText, self)
#                     @popup = KDE::PassivePopup::message("Title", @text.plainText, Qt::SystemTrayIcon::Information)
                when 3
                    @popup = KDE::PassivePopup.new
                    @popup.setView("Title", @text.plainText)
                    @popup.show
                end
            end
        end


        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(@text)
            l.addWidget(@btn)
        end
        cw = Qt::Widget.new
        cw.setLayout(lo)
        setCentralWidget(cw)
    end
end


if __FILE__ == $0
    about = KDE::AboutData.new(APP_NAME, nil, KDE::ki18n(APP_NAME), APP_VERSION)
    KDE::CmdLineArgs.init([], about)

    $app = KDE::Application.new
    args = KDE::CmdLineArgs.parsedArgs()
    win = MainWindow.new
    $app.setTopWidget(win)

    win.show
    $app.exec
end
