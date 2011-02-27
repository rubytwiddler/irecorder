require 'yaml'
require "customwidget"
#---------------------------------------------------------------------------------------
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
            attr_reader :filter
            attr_accessor :deletedFlag
            def initialize(title, categories, url, filter)
                $log.misc { "ResultEntry: title:#{title}, categories:#{categories}, url:#{url}" }
                @titleItem = Item.new(title)
                @categoriesItem = Item.new(categories)
                @durationItem = Item.new('')
                @dateItem = Item.new('')
                @urlItem = Item.new(url)
                @filter = filter
            end

            def title
                @titleItem.text
            end

            def categories
                @categoriesItem.text
            end

            def url
                @urlItem.text
            end
        end
        # end of ResultEntry class

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

            @table = {}
        end

        def addResult( title, categories, url, filter )
            entry = ResultEntry.new( title, categories, url, filter )
            row = rowCount
            self.rowCount = row + 1
            setItem( row, TITLE_COL, entry.titleItem )
            setItem( row, CATEGORIES_COL, entry.categoriesItem )
            setItem( row, DURATION_COL, entry.durationItem )
            setItem( row, DATE_COL, entry.dateItem )
            setItem( row, URL_COL, entry.urlItem )
            @table[entry.id] = entry    # column_0 for ID
        end

        def clearEntries
            clearContents
            self.rowCount = 0
            @table.each do |k,entry|
                entry.deletedFlag = true
            end
            @table = Hash.new
        end

        # return ResultEntry object.
        def [](row)
            @table[item(row,0)]
        end

        def selectedEntries
            rows = {}
            selectedIndexes.each do |index|
                rows[index.row] = true
            end

            rows.keys.map do |row|
                i = item(row, 0)
                unless @table[i] then
                    $log.error { "ResultTable selectedEntries: @table[#{i}] is nil" }
                end
                @table[i]
            end
        end
    end
    # end of ResultTable class


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
            connect( w, SIGNAL(:clicked), self, SLOT(:playProgramme) )
        end
        downloadIcon = KDE::Icon.new(':images/download-22.png')
        downloadBtn = KDE::PushButton.new( downloadIcon, i18n("Download")) do |w|
            w.objectName = 'downloadButton'
            connect( w, SIGNAL(:clicked), self, SLOT(:downloadSelected) )
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



    slots :playProgramme
    def playProgramme
        entry = @resultTable.selectedEntries[0]
        Downloader.play(entry.url) if entry
    end

    slots :downloadSelected
    def downloadSelected
        @resultTable.selectedEntries.each do |entry|
            Downloader.download( entry.title, entry.categories, entry.url, \
                                 entry.filter.folder, false )
        end
    end
end
# end of ResultTable



#---------------------------------------------------------------------------------------
class TimeSelectDlg < KDE::Dialog
    class ScheduleTimeTable < Qt::TableWidget
        class Item < Qt::TableWidgetItem
            def initialize(text)
                super(text)
                self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
                self.toolTip = text
            end
        end

        def initialize
            super(0,2)
            setHorizontalHeaderLabels(%w{Time Programme})
            horizontalHeader.stretchLastSection = true
            self.selectionBehavior = Qt::AbstractItemView::SelectRows
            self.selectionMode = Qt::AbstractItemView::SingleSelection
            self.alternatingRowColors = true
            self.sortingEnabled = false
        end

        def addTimeProgramme(time, title)
            row = rowCount
            self.rowCount = row + 1
            setItem( row, 0, Item.new(time) )
            setItem( row, 1, Item.new(title) )
        end

        def getTimeEntriesFromHtml(html)
            doc = Nokogiri::XML(html)
            broadcasts = doc.at_css("#broadcasts")
            entries = broadcasts.css(".clearfix")
            data = []
            entries.each do |entry|
                time = entry.at_css('.starttime').content
                title = entry.at_css('.title').content
                data << [time, title]
            end
            data
        end

        def addTimeSchedule(scheduleHtml)
            data = getTimeEntriesFromHtml(scheduleHtml)
            clearContents
            hide
            self.rowCount = 0
            data.each_with_index do |d, i|
                addTimeProgramme(*d)
            end
            show
        end

        def selectTime(time)
        end
    end
    # end of ScheduleTimeTable class

    def initialize(parent)
        super(parent)

        setButtons( KDE::Dialog::Cancel )
        @timeTable = ScheduleTimeTable.new

        # layout
        lw = VBoxLayoutWidget.new
        lw.addWidget(@timeTable)
        setMainWidget(lw)
    end

    def exec(scheduleHtml, selectedTime)
        @timeTable.addTimeSchedule(scheduleHtml)
        @timeTable.selectTime(selectedTime)
        super()
    end
end

#---------------------------------------------------------------------------------------
class ScheduleEditDlg < KDE::Dialog
    def initialize(parent)
        super(parent)

        setButtons( KDE::Dialog::Ok | KDE::Dialog::Cancel )

        # widgets
        @channelComboBox = Qt::ComboBox.new
        @channelComboBox.addItems( BBCNet::ChannelNameTbl )
        @timeBtn = Qt::PushButton.new('00:00')
        @intervalDaysItem = LabledRangeWidget.new(Time::RFC2822_DAY_NAME)
        @folderItem = FolderSelectorLineEdit.new('')

        # connect
        connect(@timeBtn, SIGNAL(:clicked), self, SLOT(:timePopup))

        # layout
        fl = Qt::FormLayout.new
        fl.addRow(i18n('Channel'), @channelComboBox)
        fl.addRow(i18n('Time'), @timeBtn)
        fl.addRow(i18n('Interval'), @intervalDaysItem)
        fl.addRow(i18n('Folder'), @folderItem)
        lw = VBoxLayoutWidget.new
        lw.addLayout(fl)
        setMainWidget(lw)
    end

    def exec(filter)
        interval = filter.interval
        @channel = filter.channel
        @intervalDaysItem.setRange(interval.startDay, interval.endDay)
        @folderItem.implicitParentDir = IRecSettings.downloadDir
        @folderItem.folder = filter.folder
        super()
    end

    def startDay; @intervalDaysItem.startPos; end
    def endDay; @intervalDaysItem.endPos; end
    def folder; @folderItem.folder; end

    slots :timePopup
    def timePopup
        @queryId ||= 0
        @queryId += 1
        channelIndex = BBCNet::getChannelIndex(@channel)
        reply = CachedIO::CacheReply.new(channelIndex, nil)
        reply.obj = [ @queryId  ]
        BBCNet::getScheduleHtmlByWeekdayAndChannel(startDay, channelIndex, \
                    reply.finishedMethod(self.method(:timePopupAtReadSchedule)))
    end

    def timePopupAtReadSchedule(reply)
        queryId,dmy = reply.obj
        return unless queryId == @queryId

        @timeSelectDlg ||= TimeSelectDlg.new(self)
        @timeSelectDlg.exec(reply.data, '')
    end

end
# end of ScheduleEditDlg class
#---------------------------------------------------------------------------------------




def titleStrip(t)
    t.gsub(/^[^:]+ Catch\-Up:/, '') .gsub(/:[\d\/\s]+$/, '') \
            .gsub(/:\s*Episode[\s\d]*$/, '') .gsub(/:.*$/, '')
end


#---------------------------------------------------------------------------------------
#
#  Schedule Filter Window
#
class ScheduleWindow < Qt::Widget

    SAVE_ENTRY_VERSION = '0.0.1'

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
            class Interval
                def initialize(wday)
                    raise "out of range of week days" if wday < 0 or wday > 7
                    @startDay = wday
                    @endDay = wday
                end
                attr_reader :startDay, :endDay

                def setRange(startDay, endDay)
                    startDay = [startDay, 7].min
                    endDay = [endDay, 7].min
                    if startDay < endDay then
                        @startDay = startDay
                        @endDay = endDay
                    else
                        @startDay = endDay
                        @endDay = startDay
                    end
                end

                def to_s
                    if @startDay == @endDay then
                        Time::RFC2822_DAY_NAME[@startDay]
                    else
                        Time::RFC2822_DAY_NAME[@startDay]+'-'+ \
                        Time::RFC2822_DAY_NAME[@endDay]
                    end
                end

                def ok?(wday)
                    raise "out of range of week days" if wday < 0 or wday > 7
                    wday >= @startDay and wday <= @endDay
                end
            end


            class TitleFilter
                def initialize(progInfo)
                    self.titleFilter = progInfo.title
                    @id = :title
                end
                attr_reader :id

                def setMetaInfo(minfo)
                end

                def titleFilter=(t)
                    @titleFilterRegexp = Regexp.new(titleStrip(t))
                end
                attr_reader :titleFilterRegexp
                def titleFilter
                    @titleFilterRegexp.source
                end

                def time; Time.zero; end
                def interval; nil; end
                def channel; ''; end
                def channelIndex; -1; end
            end


            class DateFilter
                def initialize(progInfo)
                    @minfo = progInfo.minfo
                    @id = :date
                    @interval = nil
                    @titleFilter = ''
                    @titleFilterRegexp = /./
                end
                attr_reader :interval
                attr_reader :titleFilter, :titleFilterRegexp
                attr_reader :id

                def setMetaInfo(minfo)
                    @minfo = minfo
                    @interval = Interval.new(minfo.onAirDate.wday)
                    @titleFilter = channel
                end

                def time
                    return @minfo.onAirDate if @minfo
                    Time.zero
                end

                def channel
                    return @minfo.channel if @minfo
                    ''
                end

                def channelIndex
                    $log.debug { "accessing channelIndex @minfo.channelIndex:#{@minfo.channelIndex}" }
                    return @minfo.channelIndex if @minfo
                    -1
                end
            end

            class SaveEntry
                attr_reader :title, :categories, :catIndex, :titleFilter, \
                        :time, :duration, :interval, :folder, :url, :orgTitle
                def initialize(filter)
                    @title = filter.title
                    @categories = filter.categories
                    @catIndex = filter.catIndex
                    @titleFilter = filter.titleFilter
                    @time = filter.time
                    @duration = filter.duration
                    @interval = filter.interval
                    @folder = filter.folder
                    @url = filter.url
                end
            end


            #
            #  ProgrammeFilter class
            #
            public
#             attr_reader :title, :orgTitle, :categories, :catIndex, :titleFilter, \
#                     :time, :duration, :interval, :folder, :url
            attr_reader :categoriesItem, :titleFilterItem, :timeItem, :durationItem, \
                    :intervalItem, :folderItem
            alias   :id :categoriesItem

            def orgTitle; @progInfo.title; end
            def categories; @progInfo.categories; end
            def catIndex; @progInfo.catIndex; end
            def url; @progInfo.url; end
            attr_accessor :folder

            def ready?; !!@progInfo.minfo; end
            def filterType; @filterData.id; end
            def titleFilter; @filterData.titleFilter; end
            def titleFilterRegexp; @filterData.titleFilterRegexp; end
            def time; @filterData.time; end     # onAirDate
            def interval; @filterData.interval; end
            def channel; @filterData.channel; end
            def duration
                return @progInfo.minfo.duration if @progInfo.minfo
                0
            end
            def channelIndex; @filterData.channelIndex; end



            protected
            def initialize
            end

            def initItems
                # TableWidgetItem
                @categoriesItem = Item.new(categories)
                @titleFilterItem = Item.new(titleFilter)
                @timeItem = Item.new(time.zero? ? '' : time.to_s)
                @durationItem = Item.new(duration == 0 ? '' : duration.to_s)
                @intervalItem = Item.new(interval ? '' : interval.to_s)
                @folderItem = Item.new(folder || '')

                @progInfo.readMetaInfo(self.method(:initOnRead))
            end

            def initOnRead(minfo)
                $log.debug { "#{self.class.name} initOnRead : minfo:#{minfo}" }
                # set folder
                if folder.nil? or folder.empty? then
                    @folderItem.text = self.folder =
                            Downloader.getSaveFolderName(minfo, @progInfo.tags)
                end

                @filterData.setMetaInfo(minfo)
                @durationItem.text = duration.to_s
                @timeItem.text = time.to_s
                @intervalItem.text = interval.to_s

                # titleFilter or channel
                @titleFilterItem.text = titleFilter
            end


            public
            def initByTitle(progInfo)
                $log.debug { "#{self.class.name}.initByTitle  initByTitle:#{progInfo}" }
                $log.debug { "title:#{progInfo.title}, categories:#{progInfo.categories}" }
                @progInfo = progInfo

                @filterData = TitleFilter.new(progInfo)
                initItems
            end

            def initByTime(progInfo)
                $log.debug { "#{self.class.name}.initByTime  initByTime:#{progInfo}" }
                $log.debug { "title:#{progInfo.title}, categories:#{progInfo.categories}" }
                @progInfo = progInfo

                @filterData = DateFilter.new(progInfo)
                initItems
            end


            def initBySaveEntry(saveEntry)
                @url = saveEntry.url
                @title = saveEntry.title
                @duration = saveEntry.duration
                @interval = saveEntry.interval
                @folder = saveEntry.folder
                initItems
            end

            def getSaveEntry
                SaveEntry.new(self)
            end

            def self.makeObjByTitle(*args)
                obj = self.new
                obj.initByTitle(*args)
                obj
            end

            def self.makeObjByTime(*args)
                obj = self.new
                obj.initByTime(*args)
                obj
            end

            def self.makeObjBySaveEntry(saveEntry)
                obj = self.new
                obj.initBySaveEntry(saveEntry)
                obj
            end
        end
        # end of ProgrammeFilter class


        #
        # ProgrammeFilterTable class
        #

        # column
        CATEGORY_COL, PROGRAM_COL, TIME_COL, DURATION_COL, INTERVAL_COL, FOLDER_COL = (0..5).to_a
        attr_reader :filters

        def initialize()
            super(0,6)

            setHorizontalHeaderLabels(%w{Category Program/Channel Time Duration Interval Folder})
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

        def addFilterByTitle( *args )
            filter = ProgrammeFilter::makeObjByTitle( *args )
            addFilter( filter )
        end

        def addFilterByTime( *args )
            filter = ProgrammeFilter::makeObjByTime( *args )
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
            setItem( 0, DURATION_COL, filter.durationItem )
            setItem( 0, INTERVAL_COL, filter.intervalItem )
            setItem( 0, FOLDER_COL, filter.folderItem )
            @table[filter.id] = filter  # column_0 for ID

            self.sortingEnabled = sortFlag
        end
    end
    # end of ProgrammeFilterTable class


    #--------------------------------------------
    #
    #  ScheduleWindow class
    #
    def initialize
        super()

        createWidget

        #
        @testResultDlg ||= TestResultDialog.new(self)
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
        channelIndices = {}
        filters.each do |f|
            next unless f.ready?
            case f.filterType
            when :title
                catIndices[f.catIndex] ||= []
                catIndices[f.catIndex].push(f)
            when :date
                channelIndices[f.channelIndex] ||= []
                channelIndices[f.channelIndex].push(f)
            end
        end
        catIndices.delete(-1)
        channelIndices.delete(-1)

        catIndices.each do |catIndex, filters|
            reply = CachedIO::CacheReply.new(catIndex, nil)
            reply.obj = filters
            BBCNet::getRssByCategoryIndex(catIndex, \
                    reply.finishedMethod(method))
        end

        channelIndices.each do |channelIndex, filters|
            reply = CachedIO::CacheReply.new(channelIndex, nil)
            reply.obj = filters
            BBCNet::getRssByChannelIndex(channelIndex, \
                    reply.finishedMethod(method))
        end
    end

    def updateFiltersAtReadRss(reply)
        rss = reply.data
        return unless rss
        filters = reply.obj
        entries = rss.css('entry')
        return unless entries and entries.size
        filters.each do |filter|
            entries.each do |e|
                title = e.at_css('title').content
                content = e.at_css('content').content
                episodeUrl = content[UrlRegexp]       # String[] method extract only 1st one.
                case filter.filterType
                when :title
                    if filter.titleFilterRegexp.match(title) then
                        downloadProgramme( filter, title, episodeUrl )
                    end
                when :date
                    if filter.titleFilterRegexp.match(title) then
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
        @queryId ||= 0
        @queryId += 1
        rss = reply.data
        return unless rss
        filters = reply.obj
        entries = rss.css('entry')
        return unless entries and entries.size
        filters.each do |filter|
            $log.debug { "testFiltersAtReadRss. entries(size:#{entries.size})" }
            entries.each do |e|
                title = e.at_css('title').content
                content = e.at_css('content').content
                categories = e.css('category').map do |c| c['term'] end.join(',')
                episodeUrl = content[UrlRegexp]       # String[] method extract only 1st one.
                case filter.filterType
                when :title
                    if filter.titleFilterRegexp.match(title) then
                        $log.debug { "testFiltersAtReadRss adding entry title:#{title}" }
                        @testResultDlg.table.addResult( title, categories, episodeUrl, filter )
                    end
                when :date
                    # check channel time
                    reply = CachedIO::CacheReply.new(episodeUrl, nil)
                    reply.obj = [ @queryId, title, categories, episodeUrl, filter ]
                    BBCNet::CachedMetaInfoIO.read(episodeUrl, \
                            reply.finishedMethod(self.method(:testFiltersAtReadInfo)))
                end
            end
        end
    end


    def testFiltersAtReadInfo(reply)
        minfo = reply.data
        queryId, title, categories, episodeUrl, filter = reply.obj
        return if queryId != @queryId
        return unless filter.channelIndex == minfo.channelIndex && \
            filter.interval.ok?(minfo.onAirDate.wday) && \
            filter.time.strftime("%H:%M") == minfo.onAirDate.strftime("%H:%M")

        @testResultDlg.table.addResult( title, categories, episodeUrl, filter )
    end


    def addFilterByTitle(progInfo)
        @programmeFilterTable.addFilterByTitle( progInfo )
    end

    def addFilterByTime(progInfo)
        @programmeFilterTable.addFilterByTime( progInfo )
    end

    slots :editFilter
    def editFilter
        filters = @programmeFilterTable.selectedFilters
        return if filters.nil? or filters.empty?
        filter = filters.first
        return unless filter.ready?

        @editDialog ||= ScheduleEditDlg.new(self)
        if @editDialog.exec(filter) == Qt::Dialog::Accepted then
            filter.interval.setRange(@editDialog.startDay, @editDialog.endDay)
            filter.intervalItem.text = filter.interval.to_s
            filter.folderItem.text = filter.folder = @editDialog.folder
        end
    end

    #
    #
    protected
    def downloadProgramme( filter, title, episodeUrl )
        # download
        $log.debug { "download item { title:#{title}, epUrl:#{episodeUrl} }" }
        folder = filter.folder.empty? ? nil : filter.folder
        Downloader.download( title, filter.categories, episodeUrl, folder, true )
    end

    def getFiltersFileName
        @filtersFileName ||= KDE::StandardDirs::locateLocal("appdata", "filters")
    end


    public
    def saveFilters
        return      #!!!!!! for debug  !!!!!!

        saveData = [SAVE_ENTRY_VERSION]
        @programmeFilterTable.filters.each do |filter|
            saveData.push( filter.getSaveEntry )
        end

        open(getFiltersFileName, 'w') do |f|
            f.puts( saveData.to_yaml )
        end
    end

    def loadFilters
        return      #!!!!!! for debug  !!!!!!

        fileName = getFiltersFileName
        return unless File.exist?(fileName)

        open(fileName) do |f|
            saveData = YAML.load(f)
            return unless saveData.shift == SAVE_ENTRY_VERSION
            @programmeFilterTable.addSaveEntries( saveData )
        end
    end
end
# end of ScheduleWindow class