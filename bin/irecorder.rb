#!/usr/bin/ruby
#
#    2010 by ruby.twiddler@gmail.com
#
#     KDE GUI Audio recorder which has similar interface to BBC iPlayer.
#      record real/wma (rtsp/mms) audio stream
#

$KCODE = 'UTF8'
require 'ftools'

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
require 'fileutils'
require 'singleton'

# additional libs
require 'korundum4'
require 'qtwebkit'

#
# my libraries and programs
#
$:.unshift(LIB_DIR)
require "irecorder_resource"
require "bbcnet"
require "mylibs"
require "logwin"
require "taskwin"
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


#         $app.styleSheet = IO.read(APP_DIR + '/resources/bbcstyle.qss')
        @actions = KDE::ActionCollection.new(self)

        createWidgets
        createMenu
        createDlg

        # default values
#         BBCNet.setProxy('http://194.36.10.154:3127')
        # initialize values
        $log = MyLogger.new(@logWin)
        $log.level = MyLogger::DEBUG
        $log.info { 'Log Start.' }

        # assign from config file.
        readSettings
        applyTheme
        @actions.readSettings
        setAutoSaveSettings(GroupName)

        initializeTaskTimer
    end



    protected
    def initializeTaskTimer
        # Task Timer
        @timer = Qt::Timer.new(self)
        connect( @timer, SIGNAL(:timeout), self, SLOT(:updateTask) )
        @timer.start(1000)          # 1000 msec = 1 sec
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

        fileMenu = KDE::Menu.new('&File', self)
        fileMenu.addAction(recordAction)
        fileMenu.addAction(reloadStyleAction)
        fileMenu.addAction(clearStyleAction)
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
        aboutDlg = KDE::AboutApplicationDialog.new($about)
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

        @mainTabPage = Qt::Splitter.new
        @topTab.addTab(@mainTabPage, 'Channels')

        @mainTabPage.addWidget(createChannelAreaWidget)

        # Main Tab page. programme table area
        @progTableFrame = Qt::Splitter.new(Qt::Vertical)
        @progTableFrame.addWidget(createProgrammeAreaWidget)
        @progTableFrame.addWidget(createProgrammeSummaryWidget)
        @mainTabPage.addWidget(@progTableFrame)

        # parameter : Qt::Splitter.setStretchFactor( int index, int stretch )
        @mainTabPage.setStretchFactor( 0, 0 )
        @mainTabPage.setStretchFactor( 1, 1 )

        # dock
        createPlayerDock


        #  Top Tab - Task Page
        @taskWin = TaskWindow.new
        @topTab.addTab(@taskWin, 'Task')

        #  Top Tab - Log Page
        @logWin = LogWindow.new
        @topTab.addTab(@logWin, 'Log')


        # set Top Widget & Layout
        setCentralWidget(@topTab)
    end


    #-------------------------------------------------------------
    #
    TvType, RadioType, RadioCategoryType = [-1,0,1]    # TvType = -1 (hide)
    TVChannelRssTbl = [
        ['BBC One', 'bbc_one' ],
        ['BBC Two', 'bbc_two' ],
        ['BBC Three', 'bbc_three' ],
        ['BBC Four', 'bbc_four' ],
        ['CBBC', 'cbbc'],
        ['CBeebies', 'cbeebies'],
        ['BBC News Channel', 'bbc_news24'],
        ['BBC Parliament', 'bbc_parliament'],
        ['BBC HD', 'bbc_hd'],
        ['BBC ALBA', 'bbc_alba'] ]

    RadioChannelRssTbl = [
        ['BBC Radio 1', 'bbc_radio_one'],
        ['BBC 1Xtra', 'bbc_1xtra'],
        ['BBC Radio 2', 'bbc_radio_two'],
        ['BBC Radio 3', 'bbc_radio_three'],
        ['BBC Radio 4', 'bbc_radio_four'],
        ['BBC Radio 5 live', 'bbc_radio_five_live'],
        ['BBC Radio 5 live sports extra', 'bbc_radio_five_live_sports_extra'],
        ['BBC 6 Music', 'bbc_6music'],
        ['BBC Radio 7', 'bbc_7'],
        ['BBC Asian Network', 'bbc_asian_network'],
        ['BBC World service', 'bbc_world_service'],
        ['BBC Radio Scotland', 'bbc_alba/scotland'],
        ['BBC Radio Nan Gàidheal', 'bbc_radio_nan_gaidheal'],
        ['BBC Radio Ulster', 'bbc_radio_ulster'],
        ['BBC Radio Foyle', 'bbc_radio_foyle'],
        ['BBC Radio Wales', 'bbc_radio_wales'],
        ['BBC Radio Cymru', 'bbc_radio_cymru'] ]

    CategoryRssTbl = [
        ['Children\'s', 'childrens'],
        ['Comedy', 'comedy'],
        ['Drama', 'drama'],
        ['Entertainment', 'entertainment'],
        ['Factual', 'factual'],
        ['Films', 'films'],
        ['Music', 'music'],
        ['News', 'news'],
        ['Learning', 'learning'],
        ['Religion & Ethics', 'religion_and_ethics'],
        ['Sport', 'sport'],
        ['Sign Zone', 'signed'],
        ['Audio Described', 'audiodescribed'],
        ['Northern Ireland', 'northern_ireland'],
        ['Scotland', 'scotland'],
        ['Wales', 'wales'] ]

    CategoryNameTbl = CategoryRssTbl.map do |c|
            c[0][/[\w\s\'&]+/].gsub(/\'/, '').gsub(/&/, ' and ')
        end
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
#         @tvChannelListBox.addItems( TVChannelRssTbl.map do |w| w[0] end )
#         toolBox.addItem( @tvChannelListBox, 'TV Channels' )


        # Radio Channels
        @radioChannelListBox = KDE::ListWidget.new
        @radioChannelListBox.addItems( RadioChannelRssTbl.map do |w| w[0] end )
        toolBox.addItem( @radioChannelListBox, 'Radio Channels' )

        # Category selector
        @categoryListBox = KDE::ListWidget.new
        @categoryListBox.addItems( CategoryRssTbl.map do |w| w[0] end )
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
        VBoxLayoutWidget.new do |vbxw|
            @programmeTable = ProgrammeTableWidget.new do |w|
                connect(w, SIGNAL('cellClicked(int,int)'),
                        self, SLOT('programmeCellClicked(int,int)'))
            end
            vbxw.addWidget(HBoxLayoutWidget.new do |hw|
                    hw.addWidget(Qt::Label.new(i18n('Look for:')))
                    hw.addWidget(
                        @filterLineEdit = KDE::LineEdit.new do |w|
                            connect(w,SIGNAL('textChanged(const QString &)'),
                                    @programmeTable, SLOT('filterChanged(const QString &)'))
                            w.setClearButtonShown(true)
                            connect(@programmeTable, SIGNAL('filterRequest(const QString &)'),
                                w, SLOT('setText(const QString &)'))
                        end
                    )
                end
            )
            vbxw.addWidget( @listTitleLabel = Qt::Label.new('') )
            vbxw.addWidget(@programmeTable)

            playIcon = KDE::Icon.new(':images/play-22.png')
            playBtn = KDE::PushButton.new( playIcon, i18n("Play")) do |w|
                w.objectName = 'playButton'
                connect( w, SIGNAL(:clicked), self, SLOT(:playProgramme) )
            end

            # 'Start Download' Button
            downloadIcon = KDE::Icon.new(':images/download-22.png')
            downloadBtn = KDE::PushButton.new( downloadIcon, i18n("Download")) do |w|
                w.objectName = 'downloadButton'
                connect( w, SIGNAL(:clicked), self, SLOT(:startDownload) )
            end

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
        @playerWevView = Qt::WebView.new do |w|
            w.page.linkDelegationPolicy = Qt::WebPage::DelegateAllLinks
        end

        webSettings = Qt::WebSettings::globalSettings
        webSettings.setAttribute(Qt::WebSettings::PluginsEnabled, true)


        @playerDock.setWidget(@playerWevView)
        self.addDockWidget(Qt::RightDockWidgetArea, @playerDock)

        @playerDock
    end

    #-------------------------------------------------------------
    #
    #
    def createDlg
        @settingsDlg = SettingsDlg.new(self)
        connect(@settingsDlg, SIGNAL(:updated), self, SLOT(:updateSettings))
    end


    slots  :configureApp
    # slot
    def configureApp
        @settingsDlg.exec
        updateSettings
    end

    slots :updateSettings
    def updateSettings
        applyTheme
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
        @mainTabPage.restoreState(config.readEntry('MainTabPageState', @mainTabPage.saveState))
        @progTableFrame.restoreState(config.readEntry('ProgTableFrame',
                                                      @progTableFrame.saveState))
        @channelTypeToolBox.currentIndex = config.readEntry('ChannelType', @channelTypeToolBox.currentIndex)

        @programmeTable.readSettings
        @taskWin.readSettings
    end

    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('MainTabPageState', @mainTabPage.saveState)
        config.writeEntry('ProgTableFrame', @progTableFrame.saveState)
        config.writeEntry('ChannelType', @channelTypeToolBox.currentIndex)

        @programmeTable.writeSettings
        @taskWin.writeSettings
#         dumpConfig(GroupName)
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
    def applyTheme
        ssfile = getStyleSheetFileName
        if ssfile then
            if @styleSheetFile and @styleSheetFile != ssfile then
                KDE::MessageBox.information(self, i18n("You changed theme. Please restart this application"))
            else
                @styleSheetFile = ssfile
                styleStr = IO.read(ssfile)
                $app.styleSheet = styleStr
                $app.styleSheet = styleStr
                $log.info { "load theme file '#{@styleSheetFile}'" }
            end
        else
            clearStyleSheet
        end
    end

    def getStyleSheetFileName
        if IRecSettings.systemDefaultTheme then
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


        def getIplayerUrl(prog)
            # big type console
            url = prog.link
            $log.info { "big console Url : #{url}" }

            # old type console
            url = prog.content[UrlRegexp]       # String[] method extract only 1st one.
            $log.info { "episode Url : #{url}" }
            url = BBCNet.getPlayerConsoleUrl(url)
            $log.info { "old console Url : #{url}" }
            url
        end

        prog = @programmeTable[items[0].row]
        webPlayerCommand = IRecSettings.webPlayerCommand
        directPlayerCommand = IRecSettings.directPlayerCommand

        begin
            if IRecSettings.useInnerPlayer then
                url = getIplayerUrl(prog)

                @playerDock.show
                @playerWevView.setUrl(Qt::Url.new(url))
            elsif IRecSettings.useWebPlayer and webPlayerCommand then
                $log.info { "Play on web browser" }
                url = getIplayerUrl(prog)
                cmd, args = makeProcCommand(webPlayerCommand, url)
                $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
                proc = Qt::Process.new(self)
                proc.start(cmd, args)

            elsif IRecSettings.useDirectPlayer and directPlayerCommand then
                $log.info { "Play direct" }
                url = prog.content[UrlRegexp]       # String[] method extract only 1st one.

                $log.info { "episode Url : #{url}" }
                minfo = BBCNet::CacheMetaInfoDevice.read(url)
                $log.debug { "#{minfo.inspect}" }
                raise "No stream Url" unless minfo.wma
                url = minfo.wma.url

                cmd, args = makeProcCommand(directPlayerCommand, url)

                $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
                proc = Qt::Process.new(self)
                proc.start(cmd, args)
            end
        rescue => e
            if e.kind_of? RuntimeError
                $log.info { e.message }
            else
                $log.error { e }
            end
            # some messages must be treated.
            # already expired.
            # some xml error.
            # no url
            passiveMessage(i18n("There is no direct stream for this programme.\n %s" %[prog.title]))
        end
    end

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

        begin
            makeTablefromRss( CacheRssDevice.read(feedAdr) )
        rescue  => e
            $log.error { e }
        end
        setListTitle
    end


    #
    # get feed address
    #
    protected
    def getFeedAdr
        @channelType = @channelTypeToolBox.currentIndex

        channelStr = nil
        case  @channelType
        when TvType
            # get TV channel
            @channelIndex = @tvChannelListBox.currentRow
            channelStr = TVChannelRssTbl[ @channelIndex ][1]
        when RadioType
            # get Radio channel
            @channelIndex = @radioChannelListBox.currentRow
            channelStr = RadioChannelRssTbl[ @channelIndex ][1]
        when RadioCategoryType
            # get Category
            @channelIndex = @categoryListBox.currentRow
            channelStr = 'categories/' + CategoryRssTbl[ @channelIndex ][1] + '/radio'
        end

        return nil  if channelStr.nil?

        @listType = @listTypeGroup.checkedId
        list = %w[ list highlights popular ][@listType]

        "http://feeds.bbc.co.uk/iplayer/#{channelStr}/#{list}"
    end


    def getCategoryTitle
        CategoryRssTbl[ @channelIndex ][0]
    end

    def setListTitle
        names = []
        if getChannelTitle
            names << getChannelTitle
        else
            names << CategoryRssTbl[ @channelIndex ][0]
        end
        names << %w[ All Highlights Popular ][@listType]
        @listTitleLabel.text = names.join(' / ')
    end

    protected
    def makeTablefromRss(rss)
        @programmeTable.clearContents
        @programmeTable.rowCount = 0
        @filterLineEdit.clear
        entries = rss.css('entry')
        return unless rss and entries and entries.size

        sortFlag = @programmeTable.sortingEnabled
        @programmeTable.sortingEnabled = false
        @programmeTable.hide
        @programmeTable.rowCount = entries.size

        # ['Title', 'Category', 'Updated' ]
        entries.each_with_index do |i, r|
            title = i.at_css('title').content
            updated = i.at_css('updated').content
            contents = i.at_css('content').content
            linkItem = i.css('link').find do |l| l['rel'] == 'self' end
            link = linkItem ? linkItem['href'] : nil
            categories = i.css('category').map do |c| c['term'] end.join(',')
            $log.misc { title }
            @programmeTable.addEntry( r, title, categories, updated, contents, link )
        end

        @programmeTable.sortingEnabled = sortFlag
        @programmeTable.show
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
            begin
                url = prog.content[UrlRegexp]       # String[] method extract only 1st one.

                $log.info { "episode Url : #{url}" }
                minfo = BBCNet::CacheMetaInfoDevice.read(url)
                url = minfo.wma.url

                fName = getSaveName(prog, 'wma')
                $log.info { "save name : #{fName}" }

                startDownOneFile(minfo, fName)

                passiveMessage(i18n("Start Download programme '%s'") % [prog.title])

            rescue Timeout::Error, StandardError => e
                if e.kind_of? RuntimeError
                    $log.info { e.message }
                else
                    $log.error { e }
                end
                passiveMessage(i18n("There is no direct stream for this programme.\n%s" %[prog.title]))
            end
        end
    end


    protected
    #
    def getSaveName(prog, ext='wma')
        tags = prog.categories.split(/,/)
        dir = getSaveSubDirName(tags)
        $log.debug { "save dir : #{dir}" }

        dir + '/' + getSaveBaseName(prog.title, tags, ext)
    end

    def getSaveBaseName(title, tags, ext)
        s = IRecSettings
        head = s.fileAddHeadStr
        head += getMediaName(tags) + ' ' if s.fileAddMediaName
        head += getChannelName + ' ' if s.fileAddChannelName and getChannelName
        head += getGenreName(tags) + ' ' if s.fileAddGenreName and getGenreName(tags)
        head += "- " unless head.empty?
        baseName = head  + title + '.' + ext
        baseName.gsub(%r{[\/]}, '-')
    end

    #
    def getSaveSubDirName(tags)
        s = IRecSettings
        dir = []
        dir << getMediaName(tags) if s.dirAddMediaName
        dir << getChannelName if s.dirAddChannelName and getChannelName
        dir << getGenreName(tags) if s.dirAddGenreName and getGenreName(tags)
        File.join(dir.compact)
    end

    # media [TV,Radio,iPod]
    def getMediaName(tags)
        tags.find do |t|
            %w(radio tv ipod).include?(t.downcase)
        end
    end

    # channel [BBC Radio 4, ..]
    def getChannelName
        getChannelTitle
    end

    def getChannelTitle
        case  @channelType
        when TvType
        # get TV channel
            TVChannelRssTbl[ @channelIndex ][0]
        when RadioType
        # get Radio channel
            RadioChannelRssTbl[ @channelIndex ][0]
        else
            nil
        end
    end

    # Main Genre [Drama, Comedy, ..]
    def getGenreName(tags)
        CategoryNameTbl.find do |cat|
            tags.find do |t|
                cat =~ /#{t}/i
            end
        end
    end


    # other genre [Sitcom, SF, etc]
    def getSubGenreName(tags)
    end





    #-------------------------------------------------------------------
    # parameter
    #  metaInfo : source stream MetaInfo of download file.
    #  fName : save file name.
    #
    # start Dwnload One file.
    protected
    def startDownOneFile(metaInfo, fName)
        process = DownloadProcess.new(self, metaInfo, fName)
        process.taskItem = @taskWin.addTask(process)
        process.beginTask
    end




    #
    # slot :  periodically called to update task view.
    #
    protected
    slots  :updateTask
    def updateTask
        @taskWin.each do |task|
            task.process.updateView
        end
    end
end


#
#    main start
#

$about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION,
                            KDE::ki18n('BBC iRecorder KDE')
                           )
$about.setProgramIconName(':images/irecorder-22.png')
$about.addLicenseTextFile(APP_DIR + '/MIT-LICENSE')
KDE::CmdLineArgs.init(ARGV, $about)
# options = KDE::CmdLineOptions.new()
# options.add( "+url", KDE::ki18n( "The url to record)" ),"")

$app = KDE::Application.new
args = KDE::CmdLineArgs.parsedArgs()
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
