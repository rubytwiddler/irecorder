#!/usr/bin/ruby
#
#    2009 by ruby.twiddler@gmail.com
#
#     IPlayer interface
#      record real/wma (rtsp/mms) audio/video stream
#

$KCODE = 'UTF8'
require 'ftools'

APP_NAME = File.basename(__FILE__).sub(/\.rb/, '')
APP_DIR = File.expand_path(File.dirname(__FILE__))
LIB_DIR = File::join(File::dirname(APP_DIR), "lib")
APP_VERSION = "0.0.1.5"

# standard libs
require 'rubygems'
require 'uri'
require 'net/http'
require 'open-uri'
require 'rss'
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
require "bbcnet"
require "mylibs"
require "logwin"
require "taskwin"
require "download"
require "settings"





#---------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------





#---------------------------------------------------------------------------------------------
#
#
class ProgrammeTableWidget < Qt::TableWidget
    slots   'filterChanged(const QString &)'

    #
    #
    class Programme
        attr_reader :titleItem, :categoriesItem, :updatedItem
        attr_reader :content, :link

        def initialize(title, categories, updated, content, link)
            @titleItem = Item.new(title)
            @categoriesItem = Item.new(categories)
            @updatedItem = Item.new(updated)
            @content = content
            @link = link
        end

        def title
            @titleItem.text
        end

        def categories
            @categoriesItem.text
        end

        def updated
            @updatedItem.text
        end
    end

    #
    #
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
            self.toolTip = text
        end
    end


    #------------------------------------------------------------------------
    #
    #
    attr_accessor :mediaFilter

    def initialize()
        super(0, 3)

        setHorizontalHeaderLabels(['Title', 'Category', 'Updated'])
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true
        self.sortingEnabled = true
        sortByColumn(2, Qt::DescendingOrder )

        @mediaFilter = ''

        # Hash table : key column_0_item  => Programme entry.
        @table = Hash.new
    end

    def addEntry( row, title, categories, updated, content, link )
        entry = Programme.new(title, categories, updated, content, link)
        setItem( row, 0, entry.titleItem )
        setItem( row, 1, entry.categoriesItem )
        setItem( row, 2, entry.updatedItem )
        @table[entry.titleItem] = entry
    end

    # return Programme object.
    def [](row)
        @table[item(row,0)]
    end


    #
    # slot : called when filterLineEdit text is changed.
    #
    public

    def filterChanged(text)
        return unless text

        text += ' ' + @mediaFilter unless @mediaFilter.empty?

        regxs = text.split(/[,\s]+/).map do |w|
                    /#{Regexp.escape(w.strip)}/i
        end
        rowCount.times do |r|
            i0 = item(r,0)
            i1 = item(r,1)
            i2 = item(r,2)
            txt = ((i0 && i0.text) || '') + ((i1 && i1.text) || '') + ((i2 && i2.text) || '')
            if regxs.all? do |rx| rx =~ txt end then
                showRow(r)
            else
                hideRow(r)
            end
        end
    end

    GroupName = "ProgrammeTable"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        horizontalHeader.restoreState(config.readEntry('Header', horizontalHeader.saveState))
    end

    protected
    def contextMenuEvent(e)
        item = itemAt(e.pos)
        menu = createPopup
        execPopup(menu, e.globalPos, item)
    end

    def createPopup()
        menu = Qt::Menu.new
        insertPlayerActions(menu)
        menu
    end

    def execPopup(menu, pos, item)
        action = menu.exec(pos)
        if action then
            action.data
#             $log.code { "execute : '#{action.vData}'" }
                cmd, exe = action.vData.split(/@/, 2)
#                 $log.code { "cmd(#{cmd}), exe(#{exe})" }
                case cmd
                when 'play'
                    playMedia(exe, item)
                else
#                     self.method(cmd).call(item)
                end
        end
        menu.deleteLater
    end

    def insertPlayerActions(menu)
        Mime::services('.wma').each do |s|
            if s.exec then
                exeName = s.exec[/\w+/]
                a = menu.addAction(KDE::Icon.new(exeName), 'Play with ' + exeName)
                a.setVData('play@' + s.exec)
            end
        end
    end

    def playMedia(exe, item)
        begin
            prog = self[item.row]
            url = prog.content[UrlRegexp]       # String[] method extract only 1st one.

            $log.info { "episode Url : #{url}" }
            minfo = BBCNet::MetaInfo.get(url).update
            url = minfo.wma.url

            cmd, args = exe.split(/\s+/, 2)
            args = args.split(/\s+/).map do |a|
                a.gsub(/%\w/, url)
            end
#             $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
            proc = Qt::Process.new(self)
            proc.start(cmd, args)

        rescue => e
            $log.error { e }
            KDE::MessageBox::information(self, i18n("There is not direct stream for this programme."))
        end
    end
end




#---------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------
#
#  Main Window Class
#
class MainWindow < KDE::MainWindow
    slots   :startDownload, :updateTask, :getList, :reloadStyleSheet, :clearStyleSheet
    slots   :mediaFilterChanged, :playProgramme
    slots   'programmeCellClicked(int,int)'

    GroupName = "MainWindow"

    #
    #
    #
    def initialize
        super(nil)
        setCaption(APP_NAME)


        $app.styleSheet = IO.read('resources/bbcstyle.qss')

        createWidgets
        createMenu
        createDlg

        # default values
#         BBCNet.setProxy('http://194.36.10.154:3127')
        # initialize values
        $log = MyLogger.new(@logWin)
        $log.level = MyLogger::INFO
        $log.info { 'Log Start.' }

        # assign from config file.
        readSettings
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
        recordAction = KDE::Action.new(KDE::Icon.new('arrow-down'), i18n('Start &Download'), self)
        reloadStyleAction = KDE::Action.new(KDE::Icon.new('view-refresh'), i18n('&Reload StyleSheet'), self)
        reloadStyleAction.setShortcut(KDE::Shortcut.new('Ctrl+R'))
        clearStyleAction = KDE::Action.new(KDE::Icon.new('list-remove'), i18n('&Clear StyleSheet'), self)
        clearStyleAction.setShortcut(KDE::Shortcut.new('Ctrl+L'))
        quitAction = KDE::Action.new(KDE::Icon.new('exit'), i18n('&Quit'), self)
        quitAction.setShortcut(KDE::Shortcut.new('Ctrl+Q'))
        fileMenu = KDE::Menu.new('&File', self)
        fileMenu.addAction(recordAction)
        fileMenu.addAction(reloadStyleAction)
        fileMenu.addAction(clearStyleAction)
        fileMenu.addAction(quitAction)

        # connect actions
        connect(recordAction, SIGNAL(:triggered), self, SLOT(:startDownload))
        connect(reloadStyleAction, SIGNAL(:triggered), self, SLOT(:reloadStyleSheet))
        connect(clearStyleAction, SIGNAL(:triggered), self, SLOT(:clearStyleSheet))
        connect(quitAction, SIGNAL(:triggered), self, SLOT(:close))

        # settings menu
        playerDockAction = @playerDock.toggleViewAction
        playerDockAction.text = i18n('Show Player')
        configureAppAction = KDE::Action.new(KDE::Icon.new('configure'),
                                              i18n("Configure #{APP_NAME}"), self)
        settingsMenu = KDE::Menu.new(i18n('&Settings'), self)
        settingsMenu.addAction(playerDockAction)
        settingsMenu.addSeparator
        settingsMenu.addAction(configureAppAction)
        # connect actions
        connect(configureAppAction, SIGNAL(:triggered), self, SLOT(:configureApp))


        # Help menu
        about = i18n(<<-ABOUT
#{APP_NAME} #{APP_VERSION}

BBC iPlayer like audio (mms/rtsp) stream recorder.
        ABOUT
        )
        helpMenu = KDE::HelpMenu.new(self, about)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( settingsMenu )
        menu.addSeparator
        menu.addMenu( helpMenu.menu )
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

        # TV & Radio Channels selector
        @tvChannelListBox = KDE::ListWidget.new
        # TV Channels
        @tvChannelListBox.addItems( TVChannelRssTbl.map do |w| w[0] end )
        toolBox.addItem( @tvChannelListBox, 'TV Channels' )

        # Radio Channels
        @radioChannelListBox = KDE::ListWidget.new
        @radioChannelListBox.addItems( RadioChannelRssTbl.map do |w| w[0] end )
        toolBox.addItem( @radioChannelListBox, 'Radio Channels' )

        # Category selector
        @categoryListBox = KDE::ListWidget.new
        @categoryListBox.addItems( CategoryRssTbl.map do |w| w[0] end )
        toolBox.addItem( @categoryListBox, 'Categories' )

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
                        end
                    )
                end
            )
            vbxw.addWidget(@programmeTable)

            # 'Start Download' Button
            @tvFilterBtn = KDE::PushButton.new(i18n("TV")) do |w|
                w.objectName = 'mediaButton'
                w.checkable = true
                w.autoExclusive = true
                connect( w, SIGNAL(:clicked), self, SLOT(:mediaFilterChanged) )
            end

            @radioFilterBtn = KDE::PushButton.new(i18n("Radio")) do |w|
                w.objectName = 'mediaButton'
                w.checkable = true
                w.autoExclusive = true
                w.checked = true
                connect( w, SIGNAL(:clicked), self, SLOT(:mediaFilterChanged) )
            end

            playBtn = KDE::PushButton.new( KDE::Icon.new('media-playback-start'), i18n("Play")) do |w|
                w.objectName = 'playButton'
                connect( w, SIGNAL(:clicked), self, SLOT(:playProgramme) )
            end

            downloadBtn = KDE::PushButton.new( KDE::Icon.new('arrow-down'), i18n("Download")) do |w|
                w.objectName = 'downloadButton'
                connect( w, SIGNAL(:clicked), self, SLOT(:startDownload) )
            end

            vbxw.addWidgets( @tvFilterBtn, @radioFilterBtn, nil, playBtn, nil, downloadBtn, nil )
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
    end


    slots  :configureApp
    # slot
    def configureApp
        @settingsDlg.exec
    end


    #-------------------------------------------------------------
    #
    # virtual function slot
    def closeEvent(event)
        writeSettings
        super(event)
    end

    def readSettings
        config = $config.group(GroupName)
        @mainTabPage.restoreState(config.readEntry('MainTabPageState', @mainTabPage.saveState))
        @progTableFrame.restoreState(config.readEntry('ProgTableFrame',
                                                      @progTableFrame.saveState))

        @programmeTable.readSettings
        @taskWin.readSettings
    end

    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('MainTabPageState', @mainTabPage.saveState)
        config.writeEntry('ProgTableFrame', @progTableFrame.saveState)

        @programmeTable.writeSettings
        @taskWin.writeSettings
    end

    # ------------------------------------------------------------------------
    # slot :
    def reloadStyleSheet
        styleStr = IO.read('resources/bbcstyle.qss')
        $app.styleSheet = styleStr
        $app.styleSheet = styleStr
        $log.info { 'Reloaded StyleSheet.' }
    end

    # slot :
    def clearStyleSheet
        $app.styleSheet = nil
        $log.info { 'Cleared StyleSheet.' }
    end


    # slot :
    def programmeCellClicked(row, column)
        prog = @programmeTable[row]
        color = "#%06x" % (@programmeSummaryWebView.palette.color(Qt::Palette::Text).rgb & 0xffffff)

        html = <<-EOF
        <font color="#{color}">
          #{prog.content}
        </font>
        EOF

        @programmeSummaryWebView.setHtml(html)
    end

    # slot :
    def mediaFilterChanged
        setMediaFilter
        @programmeTable.filterChanged(@filterLineEdit.text)
    end


    # slot
    def playProgramme
        items = @programmeTable.selectedItems
        return unless items.size > 0

        def makeProcCommand(command, url)
            cmd, args = command.split(/\s+/, 2)
            args = args.split(/\s+/).map do |a|
                a.gsub(/%\w/, url)
            end
            [ cmd, args ]
        end

        def getIplayerUrl(prog)
            # big type console
            url = prog.link
            $log.info { "big console Url : #{url}" }

            # old type console
            url = prog.content[UrlRegexp]       # String[] method extract only 1st one.
            $log.info { "episode Url : #{url}" }
            url = BBCNet.getPlayerConsoleUrl(url)
            $log.info { "old console Url : #{url}" }

            if IRecSettings.playerTypeBeta then
                url.sub!(%r{www}, 'beta')
                $log.info { "new console Url : #{url}" }
            end
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
                minfo = BBCNet::MetaInfo.get(url).update
                $log.debug { "#{minfo.inspect}" }
                url = minfo.wma.url

                cmd, args = makeProcCommand(directPlayerCommand, url)

                $log.debug { "execute cmd '#{cmd}', args '#{args.inspect}'" }
                proc = Qt::Process.new(self)
                proc.start(cmd, args)
            end
        rescue => e
            $log.error { e }
            KDE::MessageBox::information(self, i18n("There is not direct stream for this programme."))
        end
    end


    # ------------------------------------------------------------------------
    #
    # slot: called when 'Get List' Button clicked signal invoked.
    #
    public
    def getList
        feedAdr = getFeedAdr
        return if feedAdr.nil?

        $log.info{ "feeding from '#{feedAdr}'" }

        begin
            makeTablefromRss( BBCNet.read(feedAdr) )
        rescue IOError, OpenURI::HTTPError => e
            $log.error { e }
        end
        mediaFilterChanged
    end

    #
    # get feed address
    #
    protected
    def getFeedAdr
        @channelType = @channelTypeToolBox.currentIndex

        channelStr = nil
        case  @channelType
        when 0
            # get TV channel
            @channelIndex = @tvChannelListBox.currentRow
            channelStr = TVChannelRssTbl[ @channelIndex ][1]
        when 1
            # get Radio channel
            @channelIndex = @radioChannelListBox.currentRow
            channelStr = RadioChannelRssTbl[ @channelIndex ][1]
        when 2
            # get Category
            @channelIndex = @categoryListBox.currentRow
            channelStr = 'categories/' + CategoryRssTbl[ @channelIndex ][1]
        end

        return nil  if channelStr.nil?

        list = %w[ list highlights popular ][@listTypeGroup.checkedId]

        "http://feeds.bbc.co.uk/iplayer/#{channelStr}/#{list}"
    end


    protected
    def makeTablefromRss(rssRaw)
        rss = RSS::Parser.parse(rssRaw)
        sortFlag = @programmeTable.sortingEnabled
        @programmeTable.sortingEnabled = false
        @programmeTable.hide
        @programmeTable.clearContents
        @filterLineEdit.clear
        @programmeTable.rowCount = rss.entries.size
        setMediaFilter

        # ['Title', 'Category', 'Updated' ]
        rss.entries.each_with_index do |i, r|
            title = i.title.content.to_s
            updated = i.updated.content.to_s
            contents = i.content.content
            link = i.links.find do |l| l.rel == 'self' end.href
            categories = i.categories.map do |c| c.term end.join(',')
            $log.misc { title }
            @programmeTable.addEntry( r, title, categories, updated, contents, link )
        end

        @programmeTable.sortingEnabled = sortFlag
        @programmeTable.show
    end

    def setMediaFilter
        @programmeTable.mediaFilter =
            case  @channelType
            when 2
                @tvFilterBtn.enabled = true
                @radioFilterBtn.enabled = true
                @tvFilterBtn.checked ? 'tv' : 'radio'
            else
                @tvFilterBtn.enabled = false
                @radioFilterBtn.enabled = false
                ''
            end
    end


    # ------------------------------------------------------------------------
    #
    # slot : when 'Download' Button pressed.
    #
    #   Start Downloading
    #
    public
    def startDownload
        rowsSet = {}      # use Hash as Set.
        @programmeTable.selectedItems.each do |i| rowsSet[i.row] = true end

        rowsSet.keys.sort.map do |r|
            begin
                prog = @programmeTable[r]
                url = prog.content[UrlRegexp]       # String[] method extract only 1st one.

                $log.info { "episode Url : #{url}" }
                minfo = BBCNet::MetaInfo.get(url).update
                url = minfo.wma.url

                fName = getSaveName(prog, 'wma')
                $log.info { "save name : #{fName}" }

                startDownOneFile(url, fName)
            rescue => e
                $log.error { e }
                KDE::MessageBox::information(self, i18n("There is not direct stream for programme '%s'.") % [prog.title])
            end
        end
    end


    private
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
        title = getChannelTitle
    end

    def getChannelTitle
        case  @channelType
        when 0
        # get TV channel
            TVChannelRssTbl[ @channelIndex ][0]
        when 1
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
    #  source : source url of download file.
    #  fName : save file name.
    #
    # start Dwnload One file.
    protected
    def startDownOneFile(source, fName)
        process = DownloadProcess.new(self, source, fName)
        process.taskItem = @taskWin.addTask(process, source, fName)
        process.beginTask
    end




    #
    # slot :  periodically called to update task view.
    #
    protected
    def updateTask
        @taskWin.each do |task|
            task.process.updateView
        end
    end
end


#
#    main start
#

about = KDE::AboutData.new(APP_NAME, APP_NAME, KDE::ki18n(APP_NAME), APP_VERSION)
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
