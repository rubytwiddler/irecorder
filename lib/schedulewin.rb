require 'yaml'
#-------------------------------------------------------------------------------------------
#
#
#
class TestResultDialog < Qt::Dialog


    #
    #
    #
    class ResultTable < Qt::TableWidget
        TITLE_COL, CATEGORIES_COL, DURATION_COL, DATE_COL, URL_COL = (0..4).to_a

        #
        #
        class Item < Qt::TableWidgetItem
            def initialize(text)
                super(text)
                self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
                self.toolTip = text
            end
        end

        #
        #
        class ResultEntry
            attr_reader :titleItem, :categoriesItem, :durationItem, :dateItem, :urlItem
            alias :id :titleItem
            def initialize(title, categories, url)
                $log.misc { "ResultEntry: title:#{title}, categories:#{categories}, url:#{url}" }
                @titleItem = Item.new(title)
                @categoriesItem = Item.new(categories)
                @durationItem = Item.new('')
                @dateItem = Item.new('')
                @urlItem = Item.new(url)
            end

            def title
                @titleItem.text
            end

            def categories
                @categoriesItem.text
            end

            def url
                @updatedItem.text
            end
        end


        #
        # ResultTable class
        #
        def initialize
            super(0,5)
            setHorizontalHeaderLabels(%w{Title Category Duration Date Url})
            horizontalHeader.stretchLastSection = true
            self.selectionBehavior = Qt::AbstractItemView::SelectRows
#             self.selectionMode = Qt::AbstractItemView::SingleSelection
            self.alternatingRowColors = true

            @rowTable = {}
        end

        def addResult( title, categories, url )
            entry = ResultEntry.new( title, categories, url )
            row = rowCount
            self.rowCount = row + 1
            setItem( row, TITLE_COL, entry.titleItem )
            setItem( row, CATEGORIES_COL, entry.categoriesItem )
            setItem( row, DURATION_COL, entry.durationItem )
            setItem( row, DATE_COL, entry.dateItem )
            setItem( row, URL_COL, entry.urlItem )
            @rowTable[entry.id] = entry    # column_0 for ID
        end

        def clearEntries
            clearContents
            self.rowCount = 0
            @rowTable = Hash.new
        end

        # return ResultEntry object.
        def [](row)
            @rowTable[item(row,0)]
        end
    end



    #
    # TestResultDialog class
    #
    def initialize(parent)
        super(parent)

        createWidget
    end

    def createWidget
        # create widgets
        @resultTable = ResultTable.new
        playIcon = KDE::Icon.new(':images/play-22.png')
        playBtn = KDE::PushButton.new( playIcon, i18n("Play")) do |w|
            w.objectName = 'playButton'
#             connect( w, SIGNAL(:clicked), self, SLOT(:playProgramme) )
        end
        downloadIcon = KDE::Icon.new(':images/download-22.png')
        downloadBtn = KDE::PushButton.new( downloadIcon, i18n("Download")) do |w|
            w.objectName = 'downloadButton'
#             connect( w, SIGNAL(:clicked), self, SLOT(:startDownload) )
        end
        closeBtn = KDE::PushButton.new(KDE::Icon.new('dialog-close'), i18n('Close'))

        # connect
        connect(closeBtn, SIGNAL(:clicked), self, SLOT(:accept))

        #layout
        l = Qt::VBoxLayout.new
        l.addWidget(@resultTable)
        l.addWidgets(playBtn, downloadBtn, nil, closeBtn)
        setLayout(l)
    end

    def table
        @resultTable
    end

    def hideEvent(event)
        @size= size
        @headerState = @resultTable.horizontalHeader.saveState
    end

    def showEvent(event)
        if @size then
            self.size = @size
            @resultTable.horizontalHeader.restoreState(@headerState)
        end
    end

    GroupName = "TestResult"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', @headerState)
        config.writeEntry('Size', @size)
    end

    def readSettings
        config = $config.group(GroupName)
        @headerState = config.readEntry('Header', @resultTable.horizontalHeader.saveState)
        @size = config.readEntry('Size', size)
    end
end






#-------------------------------------------------------------------------------------------
#
#  Schedule Filter Window
#
class ScheduleWindow < Qt::Widget

    #--------------------------------------------
    #
    #
    class ProgrammeFilterTable < Qt::TableWidget
        #
        #
        class Item < Qt::TableWidgetItem
            def initialize(text)
                super(text)
                self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
                self.toolTip = text
            end
        end

        #
        #
        class ProgrammeFilter
            class SaveEntry
                attr_reader :title, :categories, :catIndex, :titleFilter, :time, :interval, :folder
                def initialize(filter)
                    @title = filter.title
                    @categories = filter.categories
                    @catIndex = filter.catIndex
                    @titleFilter = filter.titleFilter
                    @time = filter.time
                    @interval = filter.interval
                    @folder = filter.folder
                end
            end

            protected
            def initialize
            end

            def initItems
                # TableWidgetItem
                @categoriesItem = Item.new(@categories)
                @titleFilterItem = Item.new(@titleFilter.source)
                @timeItem = @time.zero? ? Item.new('') : Item.new(@time.to_s)
                @intervalItem = @interval.zero? ? Item.new('') : Item.new(@interval.to_s)
                @folderItem = Item.new(@folder)
            end


            public
            attr_reader :title, :categories, :catIndex, :titleFilter, :time, :interval, :folder
            attr_reader :categoriesItem, :titleFilterItem, :timeItem, :intervalItem, :folderItem
            alias   :id :categoriesItem

            def initByTitle(title, categories, folder)
                $log.debug { "title:#{title}, categories:#{categories}, folder:#{folder}" }

                @title = title
                @categories = categories
                @catIndex = BBCNet::getCategoryIndex(categories)

                # set title filter
                @titleFilter = Regexp.new( @title.gsub(/^[^:]+ Catch\-Up:/, '') \
                    .gsub(/:[\d\/\s]+$/, '') .gsub(/:\s*Episode[\s\d]*$/, '') .gsub(/:.*$/, '') )

                #
                @time = Time.zero
                @interval = Time.zero
                @folder = folder
                initItems
            end


            def initBySaveEntry(saveEntry)
                @title = saveEntry.title
                @categories = saveEntry.categories
                @catIndex = saveEntry.catIndex
                @titleFilter = saveEntry.titleFilter
                @time = saveEntry.time
                @interval = saveEntry.interval
                @folder = saveEntry.folder
                $log.debug { "initBySaveEntry: folder:#{@folder}" }
                initItems
            end

            def getSaveEntry
                SaveEntry.new(self)
            end

            def self.makeObjByTitle(title, categories, folder)
                obj = self.new
                obj.initByTitle(title, categories, folder)
                obj
            end

            def self.makeObjBySaveEntry(saveEntry)
                obj = self.new
                obj.initBySaveEntry(saveEntry)
                $log.debug { "makeObjBySaveEntry: #{obj.inspect}" }
                obj
            end
        end


        # column
        CATEGORY_COL, PROGRAM_COL, TIME_COL, INTERVAL_COL, FOLDER_COL = (0..5).to_a
        attr_reader :filters

        #
        # ProgrammeFilterTable class
        #
        def initialize()
            super(0,5)

            setHorizontalHeaderLabels(%w{Category Program Time Interval Folder})
            horizontalHeader.stretchLastSection = true
            self.selectionBehavior = Qt::AbstractItemView::SelectRows
            self.selectionMode = Qt::AbstractItemView::SingleSelection
            self.alternatingRowColors = true
            self.sortingEnabled = true

            # Hash table : key column_0_item  => Programme entry.
            @table = Hash.new
        end

        GroupName = "ScheduleFilter"
        def writeSettings
            config = $config.group(GroupName)
            config.writeEntry('Header', horizontalHeader.saveState)
        end

        def readSettings
            config = $config.group(GroupName)
            horizontalHeader.restoreState(config.readEntry('Header', horizontalHeader.saveState))
        end

        def filters
            @table.values
        end

        slots :deleteSelected
        def deleteSelected
            index = selectedIndexes[0]
            return unless index
            itemRow = index.row
            i = item(itemRow, 0)
            @table.delete(i)
            removeRow(itemRow)
        end

        def selectedFilter
            index = selectedIndexes[0]
            return unless index
            itemRow = index.row
            i = item(itemRow, 0)
            @table[i]
        end

        def selectedFilters
            rows = {}
            selectedIndexes.each do |index|
                rows[index.row] = true
            end

            rows.keys.map do |row|
                i = item(row, 0)
                unless @table[i] then
                    $log.error { "selectedFilters: @table[#{i}] is nil" }
                end
                @table[i]
            end
        end

        def addFilterByTitle( title, categories, folder )
            filter = ProgrammeFilter::makeObjByTitle(title, categories, folder)
            addFilter( filter )
        end

        def addSaveEntries( saveData )
            saveData.each do |saveEntry|
                filter = ProgrammeFilter::makeObjBySaveEntry( saveEntry )
                addFilter( filter )
            end
        end

        def addFilter( filter )
            sortFlag = sortingEnabled
            self.sortingEnabled = false

            insertRow(0)
            setItem( 0, CATEGORY_COL, filter.categoriesItem )
            setItem( 0, PROGRAM_COL, filter.titleFilterItem )
            setItem( 0, TIME_COL, filter.timeItem )
            setItem( 0, INTERVAL_COL, filter.intervalItem )
            setItem( 0, FOLDER_COL, filter.folderItem )
            @table[filter.id] = filter  # column_0 for ID

            self.sortingEnabled = sortFlag
        end
    end


    #--------------------------------------------
    #
    #  ScheduleWindow class
    #
    def initialize
        super()

        createWidget

        #
        @testResultDlg = TestResultDialog.new(self)
    end


    def createWidget
        # create widgets
        @programmeFilterTable = ProgrammeFilterTable.new
        updateAllBtn = Qt::PushButton.new(i18n("Update All"))
        editBtn = Qt::PushButton.new(i18n("Edit"))
        updateBtn = Qt::PushButton.new(i18n("Update"))
        testFilterBtn = Qt::PushButton.new(i18n("Test"))
        deleteBtn = Qt::PushButton.new(i18n("Delete"))

        #
        connect(updateAllBtn, SIGNAL(:clicked), self, SLOT(:updateAllFilters))
        connect(updateBtn, SIGNAL(:clicked), self, SLOT(:updateSelectedFilters))
        connect(testFilterBtn, SIGNAL(:clicked), self, SLOT(:testSelectedFilters))
        connect(deleteBtn, SIGNAL(:clicked), @programmeFilterTable, SLOT(:deleteSelected))
        connect(editBtn, SIGNAL(:clicked), self, SLOT(:editFilter))

        # layout
        vLayout = Qt::VBoxLayout.new
        vLayout.addWidgets(updateAllBtn, nil, editBtn, updateBtn, testFilterBtn, deleteBtn, nil)
        vLayout.addWidget(@programmeFilterTable)

        setLayout(vLayout)
    end

    def writeSettings
        @programmeFilterTable.writeSettings
        @testResultDlg.writeSettings
    end

    def readSettings
        @programmeFilterTable.readSettings
        @testResultDlg.readSettings
    end

    slots :updateAllFilters
    def updateAllFilters
        updateFilters( @programmeFilterTable.filters )
    end

    slots :updateSelectedFilters
    def updateSelectedFilters
        filters = @programmeFilterTable.selectedFilters
        return unless filters
        $log.debug { "updateSelectedFilters: filters:#{filters}" }
        updateFilters( filters )
    end

    def updateFilters(filters)
        applyToSelectedFilters( filters, self.method(:updateFiltersAtReadRss) )
    end

    def applyToSelectedFilters( filters, method )
        catIndices = {}
        filters.each do |f|
            if catIndices[f.catIndex] then
                catIndices[f.catIndex].push(f)
            else
                catIndices[f.catIndex] = [f]
            end
        end
        catIndices.delete(-1)

        catIndices.each do |catIndex, filters|
            reply = CachedIO::CacheReply.new(catIndex, nil)
            reply.obj = filters
            BBCNet::getRssByCategoryIndex(catIndex, \
                    reply.finishedMethod(method))
        end
    end

    def updateFiltersAtReadRss(reply)
        rss = reply.data
        filters = reply.obj
        entries = rss.css('entry')
        if rss and entries and entries.size then
            filters.each do |filter|
                entries.each do |e|
                    title = e.at_css('title').content
                    if filter.titleFilter.match(title) then
                        content = e.at_css('content').content
                        episodeUrl = content[UrlRegexp]       # String[] method extract only 1st one.
                        downloadProgramme( filter, title, episodeUrl )
                    end
                end
            end
        end
    end

    slots :testSelectedFilters
    def testSelectedFilters
        filters = @programmeFilterTable.selectedFilters
        return if filters.nil? or filters.empty?

        @testResultDlg.table.clearEntries
        $log.debug { "testSelectedFilters: filters:#{filters}" }
        applyToSelectedFilters( filters, self.method(:testFiltersAtReadRss) )
        @testResultDlg.exec
    end

    def testFiltersAtReadRss(reply)
        rss = reply.data
        filters = reply.obj
        entries = rss.css('entry')
        if rss and entries and entries.size then
            filters.each do |filter|
                entries.each do |e|
                    title = e.at_css('title').content
                    if filter.titleFilter.match(title) then
                        content = e.at_css('content').content
                        categories = e.css('category').map do |c| c['term'] end.join(',')
                        episodeUrl = content[UrlRegexp]       # String[] method extract only 1st one.
                        @testResultDlg.table.addResult( title, categories, episodeUrl )
                    end
                end
            end
        end
    end



    slots 'addProgrammeFilter(const QString &, const QString &)'
    def addProgrammeFilter(title, categories)
        folder = $downloader.getSaveFolder(categories)
        # add filter
        @programmeFilterTable.addFilterByTitle( title, categories, folder )
    end


    slots :editFilter
    def editFilter
        filters = @programmeFilterTable.selectedFilters
        return if filters.nil? or filters.empty?

        filters.each do |filter|

        end
    end

    #
    #
    protected
    def downloadProgramme( filter, title, episodeUrl )
        # download
        $log.debug { "download item { title:#{title}, epUrl:#{episodeUrl} }" }
        $downloader.download( title, filter.categories, episodeUrl, filter.folder )
    end

    def getFiltersFileName
        @filtersFileName ||= KDE::StandardDirs::locateLocal("appdata", "filters")
    end


    public
    def saveFilters
        saveData = []
        @programmeFilterTable.filters.each do |filter|
            saveData.push( filter.getSaveEntry )
        end

        open(getFiltersFileName, 'w') do |f|
            f.puts( saveData.to_yaml )
        end
    end

    def loadFilters
        fileName = getFiltersFileName
        return unless File.exist?(fileName)

        open(fileName) do |f|
            saveData = YAML.load(f)
            @programmeFilterTable.addSaveEntries( saveData )
        end
    end
end
