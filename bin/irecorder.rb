#!/usr/bin/ruby -Ku
# encoding: UTF-8
#    2010-2011 by ruby.twiddler@gmail.com
#
#     iRecorder is BBC radio recorder with KDE GUI like iPlayer.
#      record real/wma (rtsp/mms) audio stream
#

require 'fileutils'

APP_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
APP_NAME = File.basename(APP_FILE).sub(/\.rb/, '')
APP_DIR = File::dirname(File.expand_path(File.dirname(APP_FILE)))
LIB_DIR = File::join(APP_DIR, "lib")
APP_VERSION = "0.0.8"

# standard libs
require 'rubygems'
require 'uri'
require 'net/http'
require 'open-uri'
require 'shellwords'
require 'singleton'
require 'pp'

# additional libs
require 'korundum4'
require 'qtwebkit'

#
# my libraries and programs
#
$:.unshift(LIB_DIR)
require "irecorder_resource"
require "mylibs"
require "bbcnet"
require "logwin"
require "taskwin"
require "schedulewin"
require "download"
require "programmewin"
require "settings"

#---------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------
#
#  Main Window Class
#
class MainWindow < KDE::MainWindow

    GroupName = "MainWindow"

    #
    #
    #
    def initialize
        super(nil)
        setCaption(APP_NAME)

        $log = MyLogger.new(STDOUT)
        $log.info { 'Initializing.' }

        applyTheme
        @actions = KDE::ActionCollection.new(self)

        createWidgets
        createDlg
        createMenu
        connectSlots

        # default values
        # initialize values
        $log.setLogDevice(@logWin)
        $log.info { 'Log Start.' }

        #
        Downloader.initializeDependency(self, @taskWin)

        # assign from config file.
        readSettings
        @actions.readSettings
        setAutoSaveSettings(GroupName)

        initializeTaskTimer
    end



    protected
    def initializeTaskTimer
        # Task Timer
        @timer = Qt::Timer.new(self)
        connect( @timer, SIGNAL(:timeout), @taskWin, SLOT(:update) )
        @timer.start(1000)          # 1000 msec = 1 sec
    end

    #
    #
    #
    def connectSlots
        @programmeTable.addListener(:addFilterByTitle, @scheduleWin.method(:addFilterByTitle))
        @programmeTable.addListener(:addFilterByTime, @scheduleWin.method(:addFilterByTime))
    end

    #
    # make menus for MainWindow
    #
    def createMenu

        # File menu
        recordAction = @actions.addNew(i18n('Start Download'), self, \
            { :icon => 'arrow-down', :triggered => :startDownload })
        reloadStyleAction = @actions.addNew(i18n('&Reload StyleSheet'), self, \
            { :icon => 'view-refresh', :shortCut => 'Ctrl+R', :triggered => :reloadStyleSheet })
        clearStyleAction = @actions.addNew(i18n('&Clear StyleSheet'), self, \
            { :icon => 'list-remove', :shortCut => 'Ctrl+L', :triggered => :clearStyleSheet })
        quitAction = @actions.addNew(i18n('&Quit'), self, \
            { :icon => 'application-exit', :shortCut => 'Ctrl+Q', :triggered => :close })

        updateScheduleAction = @actions.addNew(i18n('Update Schedule'), @scheduleWin, \
            { :shortCut => 'Ctrl+U', :triggered => :updateAllFilters })

        fileMenu = KDE::Menu.new('&File', self)
        fileMenu.addAction(recordAction)
        fileMenu.addAction(reloadStyleAction)
        fileMenu.addAction(clearStyleAction)
        fileMenu.addAction(updateScheduleAction)
        fileMenu.addAction(quitAction)


        # settings menu
        playerDockAction = @playerDock.toggleViewAction
        playerDockAction.text = i18n('Show Player')
        configureAppAction = @actions.addNew(i18n('Configure %s') % APP_NAME, self, \
            { :icon => 'configure', :shortCut => 'F2', :triggered => :configureApp })

        settingsMenu = KDE::Menu.new(i18n('&Settings'), self)
        settingsMenu.addAction(playerDockAction)
        settingsMenu.addSeparator
        settingsMenu.addAction(configureAppAction)


        # Help menu
        aboutDlg = KDE::AboutApplicationDialog.new(KDE::CmdLineArgs.aboutData)
        openAboutAction = @actions.addNew(i18n('About %s') % APP_NAME, self, \
            { :icon => 'irecorder', :triggered =>[aboutDlg, :exec] })
        openDocUrlAction = @actions.addNew(i18n('Open Document Wiki'), self, \
            { :icon => 'help-contents', :triggered =>:openDocUrl})
        openReportIssueUrlAction = @actions.addNew(i18n('Report Bug'), self, \
            { :icon => 'tools-report-bug', :triggered =>:openReportIssueUrl })
        openRdocAction = @actions.addNew(i18n('Open Rdoc'), self, \
            { :icon => 'help-contents', :triggered =>:openRdoc })
        openSourceAction = @actions.addNew(i18n('Open Source Folder'), self, \
            { :icon => 'document-open-folder', :triggered =>:openSource })


        helpMenu = KDE::Menu.new(i18n('&Help'), self)
        helpMenu.addAction(openDocUrlAction)
        helpMenu.addAction(openReportIssueUrlAction)
        helpMenu.addAction(openRdocAction)
        helpMenu.addAction(openSourceAction)
        helpMenu.addSeparator
        helpMenu.addAction(openAboutAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( settingsMenu )
        menu.addSeparator
        menu.addMenu( helpMenu )
        setMenuBar(menu)
    end




    #-------------------------------------------------------------
    #
    # create Widgets for MainWindow
    #
    def createWidgets
        @topTab = KDE::TabWidget.new

        @mainTabPageHSplitter = Qt::Splitter.new
        @topTab.addTab(@mainTabPageHSplitter, 'Channels')

        @mainTabPageHSplitter.addWidget(createChannelAreaWidget)

        # Main Tab page. programme table area
        @progTableFrame = Qt::Splitter.new(Qt::Vertical)
        @progTableFrame.addWidget(createProgrammeAreaWidget)
        @progTableFrame.addWidget(createProgrammeSummaryWidget)
        @mainTabPageHSplitter.addWidget(@progTableFrame)

        # parameter : Qt::Splitter.setStretchFactor( int index, int stretch )
        @mainTabPageHSplitter.setStretchFactor( 0, 0 )
        @mainTabPageHSplitter.setStretchFactor( 1, 1 )

        # dock
        createPlayerDock


        #  Top Tab - Task Page
        @taskWin = TaskWindow.new
        @topTab.addTab(@taskWin, 'Task')

        #  Top Tab - Schedule Page
        @scheduleWin = ScheduleWindow.new
        @topTab.addTab(@scheduleWin, 'Schedule')

        #  Top Tab - Log Page
        @logWin = LogWindow.new
        @topTab.addTab(@logWin, 'Log')


        # set Top Widget & Layout
        setCentralWidget(@topTab)
    end


    #-------------------------------------------------------------
    #
    TvType, RadioType, RadioCategoryType = [-1,0,1]    # TvType = -1 (hide)


    #
    def createChannelListToolBox
        toolBox = Qt::ToolBox.new do |w|
            w.objectName = 'channelToolBox'
        end

        # default value
        toolBox.currentIndex = 2

        # TV & Radio Channels selector
#         @tvChannelListBox = KDE::ListWidget.new
#         # TV Channels
#         @tvChannelListBox.addItems( BBCNet::TVChannelRssTbl.map do |w| w[0] end )
#         toolBox.addItem( @tvChannelListBox, 'TV Channels' )


        # Radio Channels
        @radioChannelListBox = KDE::ListWidget.new
        @radioChannelListBox.addItems( BBCNet::RadioChannelRssTbl.map do |w| w[0] end )
        toolBox.addItem( @radioChannelListBox, 'Radio Channels' )

        # Category selector
        @categoryListBox = KDE::ListWidget.new
        @categoryListBox.addItems( BBCNet::CategoryRssTbl.map do |w| w[0] end )
        toolBox.addItem( @categoryListBox, 'Radio Categories' )

        toolBox
    end

    #-------------------------------------------------------------
    #
    # [ All / Highlights / Most Popular ] selector
    #
    def createListTypeButtons
        @listTypeGroup = Qt::ButtonGroup.new
        allBtn = KDE::PushButton.new('All') do |w|
            w.objectName = 'switchButton'
            w.checkable = true
            w.autoExclusive = true
            connect(w, SIGNAL(:clicked), self, SLOT(:getList))
        end

        highlightsBtn = KDE::PushButton.new('Highlights') do |w|
            w.objectName = 'switchButton'
            w.setMinimumWidth(80)
            w.checkable = true
            w.autoExclusive = true
            connect(w, SIGNAL(:clicked), self, SLOT(:getList))
        end

        mostBtn = KDE::PushButton.new('Most Popular') do |w|
            w.objectName = 'switchButton'
            w.checkable = true
            w.autoExclusive = true
            connect(w, SIGNAL(:clicked), self, SLOT(:getList))
        end
        listTypeHLayout = Qt::HBoxLayout.new
        listTypeHLayout.addWidget(allBtn, 54)        # 2nd parameter is stretch.
        listTypeHLayout.addWidget(highlightsBtn, 180)
        listTypeHLayout.addWidget(mostBtn,235)

        @listTypeGroup.addButton(allBtn, 0)
        @listTypeGroup.addButton(highlightsBtn, 1)
        @listTypeGroup.addButton(mostBtn, 2)
        @listTypeGroup.exclusive = true

        listTypeHLayout
    end


    #-------------------------------------------------------------
    #
    # Left Side Channel ToolBox & ListType Buttons
    def createChannelAreaWidget
        VBoxLayoutWidget.new do |vb|
            @channelTypeToolBox = createChannelListToolBox
            vb.addWidget(@channelTypeToolBox)
            vb.addLayout(createListTypeButtons)
        end
    end

    #-------------------------------------------------------------
    #
    #
    def createProgrammeAreaWidget
        @programmeTable = ProgrammeTableWidget.new do |w|
            connect(w, SIGNAL('cellClicked(int,int)'),
                    self, SLOT('programmeCellClicked(int,int)'))
        end
        @filterLineEdit = KDE::LineEdit.new do |w|
            connect(w,SIGNAL('textChanged(const QString &)'),
                    @programmeTable, SLOT('filterChanged(const QString &)'))
            w.setClearButtonShown(true)
            connect(@programmeTable, SIGNAL('filterRequest(const QString &)'),
                w, SLOT('setText(const QString &)'))
        end
        @tagLabels = %w{Drama SciFi Crime Thriller Science}.map do |l|
            ClickableLabel.new(l) do |w|
                w.text = l
                w.visible = true
                connect(w, SIGNAL(:clicked), self, SLOT(:tagClicked))
            end
        end
        playIcon = KDE::Icon.new(':images/play-22.png')
        playBtn = KDE::PushButton.new( playIcon, i18n("Play")) do |w|
            w.objectName = 'playButton'
            connect( w, SIGNAL(:clicked), self, SLOT(:playProgramme) )
        end
        @listTitleLabel = ClickableLabel.new('Channel')
        connect(@listTitleLabel , SIGNAL(:clicked), self, SLOT(:channelViewToggle))

        # 'Start Download' Button
        downloadIcon = KDE::Icon.new(':images/download-22.png')
        downloadBtn = KDE::PushButton.new( downloadIcon, i18n("Download")) do |w|
            w.objectName = 'downloadButton'
            connect( w, SIGNAL(:clicked), self, SLOT(:startDownload) )
        end

        # layout
        VBoxLayoutWidget.new do |vbxw|
            vbxw.addWidgets( *([Qt::Label.new(i18n('Look for:')),
                       @filterLineEdit, @tagLabels].flatten))
            vbxw.addWidget( @listTitleLabel )
            vbxw.addWidget(@programmeTable)
            vbxw.addWidgets( nil, playBtn, nil, downloadBtn, nil )
        end
    end

    #-------------------------------------------------------------
    #
    #
    def createProgrammeSummaryWidget
        @programmeSummaryWebView = Qt::WebView.new do |w|
            w.page.linkDelegationPolicy = Qt::WebPage::DelegateAllLinks
        end
    end

    #-------------------------------------------------------------
    #
    #
    def createPlayerDock
        @playerDock = Qt::DockWidget.new(self) do |w|
            w.objectName = 'playerDock'
            w.windowTitle = i18n('Player')
            w.allowedAreas = Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea | Qt::BottomDockWidgetArea
            w.floating = true
            w.hide
        end
        @playerWebView = Qt::WebView.new do |w|
            w.page.linkDelegationPolicy = Qt::WebPage::DelegateAllLinks
        end

        webSettings = Qt::WebSettings::globalSettings
        webSettings.setAttribute(Qt::WebSettings::PluginsEnabled, true)


        @playerDock.setWidget(@playerWebView)
        self.addDockWidget(Qt::RightDockWidgetArea, @playerDock)

        @playerDock
    end

    #-------------------------------------------------------------
    #
    #
    def createDlg
        @settingsDlg = SettingsDlg.new(self)
    end


    slots  :configureApp
    # slot
    def configureApp
        @settingsDlg.exec
        if themeUpdated? then
            Qt::Timer::singleShot(0, self, SLOT(:reloadStyleSheet))
        end
    end


    #-------------------------------------------------------------
    #
    # virtual function slot
    def closeEvent(event)
        writeSettings
        super(event)
        $config.sync    # important!  qtruby can't invoke destructor properly.
    end

    def readSettings
        config = $config.group(GroupName)
        $log.level = config.readEntry('LogLevel', MyLogger::DEBUG)
        @mainTabPageHSplitter.restoreState(config.readEntry('MainTabPageState', @mainTabPageHSplitter.saveState))
        @progTableFrame.restoreState(config.readEntry('ProgTableFrame',
                                                      @progTableFrame.saveState))
        @channelTypeToolBox.currentIndex = config.readEntry('ChannelType', @channelTypeToolBox.currentIndex)
        @channelViewWidth = config.readEntry('ChannelViewWidth', 150)
        sizes = @mainTabPageHSplitter.sizes
        sizes[0] = @channelViewWidth
        @mainTabPageHSplitter.setSizes(sizes)

        @programmeTable.readSettings
        @taskWin.readSettings
        @scheduleWin.readSettings

        @scheduleWin.loadFilters
    end


    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('MainTabPageState', @mainTabPageHSplitter.saveState)
        config.writeEntry('ProgTableFrame', @progTableFrame.saveState)
        config.writeEntry('ChannelType', @channelTypeToolBox.currentIndex)
        config.writeEntry('ChannelViewWidth', @channelViewWidth)
        config.writeEntry('LogLevel', $log.level)

        @programmeTable.writeSettings
        @taskWin.writeSettings
        @scheduleWin.writeSettings
#         dumpConfig(GroupName)

        @scheduleWin.saveFilters
    end

    def dumpConfig(group)
        puts "dump #{group} config"
        entries  = KDE::Global.config.entryMap(group)
        confGroup = KDE::Global.config.group(group)
        entries.each do |key, val|
            puts "     key(#{key}) = #{val.inspect}"
        end
    end


    # -----------------------------------------------------------------------
    def themeUpdated?
        @styleSheetFile != getStyleSheetFileName
    end

    def applyTheme
        $log.info { "apply theme" }
        ssfile = getStyleSheetFileName
        if ssfile then
            if @styleSheetFile and @styleSheetFile != ssfile then
                KDE::MessageBox.information(self, i18n("You changed theme. Please restart this application"))
            else
                @styleSheetFile = ssfile
                $log.info { "load theme file '#{@styleSheetFile}'" }
                styleStr = IO.read(ssfile)
                $app.styleSheet = styleStr
                $app.styleSheet = styleStr
                $log.info { "loaded theme file '#{@styleSheetFile}'" }
            end
        else
            clearStyleSheet
        end
    end

    def getStyleSheetFileName
        if IRecSettings.instance.systemDefaultTheme then
            themeFile = nil
        elsif IRecSettings.bbcTheme then
            themeFile = APP_DIR + '/resources/bbcstyle.qss'
        elsif IRecSettings.loadTheme and File.readable?(IRecSettings.themeFile) then
            themeFile = IRecSettings.themeFile
        else
            themeFile = nil
        end
        themeFile
    end

    slots  :reloadStyleSheet
    def reloadStyleSheet
        applyTheme
        $log.info { 'Reloaded StyleSheet.' }
    end

    slots   :clearStyleSheet
    def clearStyleSheet
        $app.styleSheet = nil
        $log.info { 'Cleared StyleSheet.' }
    end


    # slot :
    slots   'programmeCellClicked(int,int)'
    def programmeCellClicked(row, column)
        prog = @programmeTable[row]
        color = "#%06x" % (@programmeSummaryWebView.palette.color(Qt::Palette::Text).rgb & 0xffffff)

        html = <<-EOF
        <style type="text/css">
        img { float: left; margin: 4px; }
        </style>
        <font color="#{color}">
          #{prog.content}
        </font>
        EOF

        @programmeSummaryWebView.setHtml(html)
    end


    slots :channelViewToggle
    def channelViewToggle
        sizes = @mainTabPageHSplitter.sizes
        if sizes[0] == 0 then
            sizes[0] = @channelViewWidth || 140
            @mainTabPageHSplitter.setSizes(sizes)
        else
            @channelViewWidth = sizes[0]
            sizes[0] = 0
            @mainTabPageHSplitter.setSizes(sizes)
        end
    end

    slots :tagClicked
    def tagClicked
        @filterLineEdit.setText(sender.text)
    end


    def makeProcCommand(command, url)
        cmd, args = command.split(/\s+/, 2)
        args = args.split(/\s+/).map do |a|
            a.gsub(/%\w/, url)
        end
        [ cmd, args ]
    end

    slots   :playProgramme
    def playProgramme
        items = @programmeTable.selectedItems
        return unless items.size > 0

        prog = @programmeTable[items[0].row]
        Downloader.play(prog.link)
    end


    public
    slots :openDocUrl
    def openDocUrl
        openUrlDocument('http://github.com/rubytwiddler/irecorder/wiki')
    end

    slots :openReportIssueUrl
    def openReportIssueUrl
        openUrlDocument('http://github.com/rubytwiddler/irecorder/issues')
    end

    slots :openRdoc
    def openRdoc
        @@gemPath ||= %x{ gem environment gempath }.split(/:/)
        relPath = '/doc/' + APP_NAME + '-' + APP_VERSION + '/rdoc/index.html'
        topPath = @@gemPath.find do |p|
            File.exist?(p + relPath)
        end
        return unless topPath
        openUrlDocument(topPath + relPath)
    end

    slots  :openSource
    def openSource
        openDirectory(APP_DIR)
    end

    def openUrlDocument(url)
        webPlayerCommand = IRecSettings.webPlayerCommand
        cmd, args = makeProcCommand(webPlayerCommand, url)
        $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
        proc = Qt::Process.new(self)
        proc.start(cmd, args)
    end

    def playWithInnerPlayer(url)
        @playerDock.show
        @playerWebView.setUrl(url)
    end

    # ------------------------------------------------------------------------
    #
    # slot: called when 'Get List' Button clicked signal invoked.
    #
    public
    slots  :getList
    def getList
        feedAdr = getFeedAdr
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }

        rss = CachedRssIO.read(feedAdr)
        makeTablefromRss( rss )
        setListTitle
    end

    #
    # get feed address
    #
    def getFeedAdr
        @channelType = @channelTypeToolBox.currentIndex

        channelStr = nil
        case  @channelType
        when TvType
            # get TV channel
            @channelIndex = @tvChannelListBox.currentRow
            channelStr = BBCNet::TVChannelRssTbl[ @channelIndex ][1]
        when RadioType
            # get Radio channel
            @channelIndex = @radioChannelListBox.currentRow
            channelStr = BBCNet::RadioChannelRssTbl[ @channelIndex ][1]
        when RadioCategoryType
            # get Category
            @channelIndex = @categoryListBox.currentRow
            channelStr = 'categories/' + BBCNet::CategoryRssTbl[ @channelIndex ][1] + '/radio'
        end

        return nil  if channelStr.nil?

        @listType = @listTypeGroup.checkedId
        list = %w[ list highlights popular ][@listType]

        "http://feeds.bbc.co.uk/iplayer/#{channelStr}/#{list}"
    end


    def getCategoryTitle
        BBCNet::CategoryRssTbl[ @channelIndex ][0]
    end

    def setListTitle
        names = []
        if getChannelTitle
            names << getChannelTitle
        else
            names << BBCNet::CategoryRssTbl[ @channelIndex ][0]
        end
        names << %w[ All Highlights Popular ][@listType]
        @listTitleLabel.text = names.join(' / ')
    end

    protected
    def makeTablefromRss(rss)
        @filterLineEdit.clear
        @programmeTable.addEntriesFromRss(rss)
    end




    # ------------------------------------------------------------------------
    #
    # slot : when 'Download' Button pressed.
    #
    #   Start Downloading
    #
    public
    slots  :startDownload
    def startDownload
        rowsSet = {}      # use Hash as Set.
        @programmeTable.selectedItems.each do |i| rowsSet[i.row] = true end

        titles = {}
        rowsSet.keys.map do |r|
            @programmeTable[r]
        end .each do |p| titles[p.title] = p end

        titles.each_value do |prog|
            $log.info { "download episode Url : #{prog.url}" }
            Downloader.download( prog.title, prog.categories, prog.url )
        end
    end




    #
    #
    protected
    def getChannelTitle
        case  @channelType
        when TvType
        # get TV channel
            BBCNet::TVChannelRssTbl[ @channelIndex ][0]
        when RadioType
        # get Radio channel
            BBCNet::RadioChannelRssTbl[ @channelIndex ][0]
        else
            nil
        end
    end
end


#
#    main start
#

about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION,
                            KDE::ki18n('BBC iRecorder KDE')
                           )
about.setProgramIconName(':images/irecorder-22.png')
about.addLicenseTextFile(APP_DIR + '/MIT-LICENSE')
KDE::CmdLineArgs.init(ARGV, about)
# options = KDE::CmdLineOptions.new()
# options.add( "+url", KDE::ki18n( "The url to record)" ),"")

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
