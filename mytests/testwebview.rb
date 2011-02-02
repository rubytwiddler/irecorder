require 'Qt'
require 'qtwebkit'

require '../lib/mylibs'

class MainWindow < Qt::MainWindow
    def initialize
        super(nil)

        # create widgets
        @addressLine = Qt::LineEdit.new
        @addressLine.text = 'http://www.bbc.co.uk/iplayer/console/b007jlb2'
        @goBtn = Qt::PushButton.new('Go') do |w|
            connect(w,SIGNAL(:clicked), self, SLOT(:go))
        end
        @playerWebview = Qt::WebView.new
        webSettings = Qt::WebSettings::globalSettings
        webSettings.setAttribute(Qt::WebSettings::PluginsEnabled, true)

        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidgets(@addressLine, @goBtn)
            l.addWidget(@playerWebview)
        end
        win = Qt::Widget.new
        win.setLayout(lo)
        setCentralWidget(win)
    end

    slots :go
    def go
        url = @addressLine.text
        if url and ! url.empty? then
            @playerWebview.setUrl(Qt::Url.new(url))
        end
    end
end


app = Qt::Application.new(ARGV)
win = MainWindow.new
win.show
app.exec

