require 'yaml'

#-------------------------------------------------------------------------------------------
#
#  Task Window
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
                @timeItem = @time == Time.at(0) ? Item.new('') : Item.new(@time.to_s)
                @intervalItem = @interval == Time.at(0) ? Item.new('') : Item.new(@interval.to_s)
                @folderItem = Item.new(@folder)
            end


            public
            attr_reader :title, :categories, :catIndex, :titleFilter, :time, :interval, :folder
            attr_reader :categoriesItem, :titleFilterItem, :timeItem, :intervalItem, :folderItem

            def initByCategory(title, categories, folder)
                $log.debug { "title:#{title}, categories:#{categories}, folder:#{folder}" }

                @title = title
                @categories = categories
                @catIndex = BBCNet::getCategoryIndex(categories)

                # set title filter
                @titleFilter = Regexp.new( @title.gsub(/^[^:]+ Catch\-Up:/, '') \
                    .gsub(/:[\d\/\s]+$/, '') .gsub(/:\s*Episode[\s\d]*$/, '') .gsub(/:.*$/, '') )

                #
                @time = Time.at(0)
                @interval = Time.at(0)
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
                initItems
            end

            def getSaveEntry
                SaveEntry.new(self)
            end

            def self.makeObjByCategory(title, categories, folder)
                obj = self.new
                obj.initByCategory(title, categories, folder)
                obj
            end

            def self.makeObjBySaveEntry(saveEntry)
                obj = self.new
                obj.initBySaveEntry(saveEntry)
                obj
            end
        end


        # column
        CATEGORY_COL, PROGRAM_COL, TIME_COL, INTERVAL_COL, FOLDER_COL = (0..5).to_a

        attr_reader :filters
        def initialize()
            super(0,5)

            self.setHorizontalHeaderLabels(%w{Category Program Time Interval Folder})
            self.horizontalHeader.stretchLastSection = true
            self.selectionBehavior = Qt::AbstractItemView::SelectRows
            self.selectionMode = Qt::AbstractItemView::SingleSelection
            self.alternatingRowColors = true

            # Hash table : key column_0_item  => Programme entry.
            @table = Hash.new
        end

        def filters
            @table.values
        end

        def addFilterByTitle( title, categories, folder )
            filter = ProgrammeFilter::makeObjByCategory(title, categories, folder)
            addFilter( filter )
        end

        def addSaveEntries( saveData )
            saveData.each do |saveEntry|
                filter = ProgrammeFilter::makeObjBySaveEntry( saveEntry )
                addFilter( filter )
            end
        end

        def addFilter( filter )
            row = rowCount
            self.rowCount = row + 1
            setItem( row, CATEGORY_COL, filter.categoriesItem )
            setItem( row, PROGRAM_COL, filter.titleFilterItem )
            setItem( row, TIME_COL, filter.timeItem )
            setItem( row, INTERVAL_COL, filter.intervalItem )
            setItem( row, FOLDER_COL, filter.folderItem )
            @table[filter.categoriesItem] = filter
        end
    end


    #--------------------------------------------
    #
    #
    def initialize
        super()

        createWidget
    end


    def createWidget
        # create widgets
        @programmeFilterTable = ProgrammeFilterTable.new

        # layout
        vLayout = Qt::VBoxLayout.new
        vLayout.addWidget(@programmeFilterTable)

        setLayout(vLayout)
    end


    slots :updateFilteredProgrammes
    def updateFilteredProgrammes
        catIndices = {}
        @programmeFilterTable.filters.each do |f|
            if catIndices[f.catIndex] then
                catIndices[f.catIndex].push(f)
            else
                catIndices[f.catIndex] = [f]
            end
        end
        catIndices.delete(-1)

        catIndices.each do |catIndex, filters|
            rss = BBCNet::getRssByCategoryIndex(catIndex)
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
    end

    slots 'addProgrammeFilter(const QString &, const QString &)'
    def addProgrammeFilter(title, categories)
        folder = $downloader.getSaveFolder(categories)
        # add filter
        @programmeFilterTable.addFilterByTitle( title, categories, folder )
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
