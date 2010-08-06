#
#    2007 by ruby.twiddler@gmail.com
#
require 'kio'


#--------------------------------------------------------------------------
#
# select from traders, system menu, arbitarary file.
#
class SelectServiceDlg < KDE::Dialog
    def initialize(parent)
        super(parent)
        @message = i18n('Select Application')
        userInitialize
        @selectedName = @services[0].name
        createWidget
    end

    def userInitialize
        @message = i18n('Select Application for .html file.')
        @services = MimeServices::getServices('.html')
    end

    def name
        @selectedName
    end

    def accept
        @selectedName = @serviceList.selectedItems.first.text
        super
    end

    def commandFromName(name)
        name.gsub!(/&/, '')
        puts "commandFromName : name : #{name}"
        item = @services.find do |i| i.name == name end
        puts "commandFromName : item : #{item.inspect}"
        item ? item.exec : nil
    end

    protected
    def createWidget
        mainWidget = VBoxLayoutWidget.new
        mainWidget.addWidget(Qt::Label.new(@message))
        @serviceList = KDE::ListWidget.new
        @serviceList.addItems( @services.map do |s| s.name end )
        @selectFromMenu = KDE::PushButton.new(i18n('Select Other from Menu'))
        mainWidget.addWidget(@serviceList)
#         mainWidget.addWidget(@selectFromMenu)

        setMainWidget(mainWidget)
    end

    class MimeServices
        AllOk = Proc.new do |s| true end

        def self.getServices(url, filterProc = AllOk)
            mimeType = KDE::MimeType.findByUrl(KDE::Url.new(url))
            mime = mimeType.name
            services = KDE::MimeTypeTrader.self.query(mime)

            services.inject([]) do |l, s|
                if s.exec and filterProc[s] then
                    l << s
                end
                l
            end
        end
    end

end


class SelectWebPlayerDlg < SelectServiceDlg
    def userInitialize
        @message = i18n('Select Web Player for iPlayer page.')
        htmlAppFilter = Proc.new do |s|
            s.name !~ /office/i and
            s.serviceTypes.find do |st|
                st =~ /application\//
            end
        end
        @services = MimeServices::getServices('.html', htmlAppFilter)
    end
end

class SelectDirectPlayerDlg < SelectServiceDlg
    def userInitialize
        @message = i18n('Select Direct Stream Player.')
        @services = MimeServices::getServices('.wma')
    end
end

#--------------------------------------------------------------------------
#
# IRecorder Settings
#
class IRecSettings < SettingsBase
    def initialize
        super()

        setCurrentGroup("Preferences")

        # meta programed version.
        addUrlItem(:rawDownloadDir, Qt::Dir::tempPath + '/RadioRaw')
        addUrlItem(:downloadDir, KDE::GlobalSettings.musicPath)
        addBoolItem(:dirAddMediaName, true)
        addBoolItem(:dirAddChannelName, false)
        addBoolItem(:dirAddGenreName, true)
        addStringItem(:fileAddHeadStr, 'BBC ')
        addBoolItem(:fileAddMediaName, true)
        addBoolItem(:fileAddChannelName, false)
        addBoolItem(:fileAddGenreName, true)
        addBoolItem(:leaveRawFile, false)

        addBoolItem(:playerTypeSmall, false)
        addBoolItem(:playerTypeBeta, true)

        addBoolItem(:useInnerPlayer, true)
        addBoolItem(:useWebPlayer, false)
        addStringItem(:webPlayerName, 'Konqueror')
        addBoolItem(:useDirectPlayer, false)
        addStringItem(:directPlayerName, 'KMPlayer')
    end

    def webPlayerCommand
        @webPlayerCnv.commandFromName(self.webPlayerName)
    end

    def self.webPlayerCommand
        self.instance.webPlayerCommand
    end

    def directPlayerCommand
        @directPlayerCnv.commandFromName(self.directPlayerName)
    end

    def self.directPlayerCommand
        self.instance.directPlayerCommand
    end

    def regConverter(webPlayerCnv, directPlayerCnv)
        @webPlayerCnv = webPlayerCnv
        @directPlayerCnv = directPlayerCnv
    end
end


#--------------------------------------------------------------------------
#
#
class SettingsDlg < KDE::ConfigDialog
    def initialize(parent)
        super(parent, "Settings", IRecSettings.instance)
        addPage(FolderSettingsPage.new, i18n("Folder"), 'folder', i18n('Folder and File Name'))
        addPage(PlayerSettingsPage.new, i18n("Player"), 'internet-web-browser', i18n('Player and web Browser'))
    end
end


#--------------------------------------------------------------------------
#
#
class FolderSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    protected

    def createWidget
        @rawFileDirLine = KDE::UrlRequester.new(KDE::Url.new(KDE::GlobalSettings.downloadPath))
        @rawFileDirLine.mode = KDE::File::Directory | KDE::File::LocalOnly

        @downloadDirLine = KDE::UrlRequester.new(KDE::Url.new(KDE::GlobalSettings.downloadPath))
        @downloadDirLine.mode = KDE::File::Directory | KDE::File::LocalOnly

        @dirSampleLabel = Qt::Label.new('Example) ')
        @dirAddMediaName = Qt::CheckBox.new(i18n('Add media directory'))
        @dirAddChannelName = Qt::CheckBox.new(i18n('Add channel directory'))
        @dirAddGenreName = Qt::CheckBox.new(i18n('Add genre directory'))
        [ @dirAddMediaName, @dirAddChannelName, @dirAddGenreName ].each do |w|
            w.connect(SIGNAL('stateChanged(int)')) do |s| updateSampleDirName end
        end

        @fileSampleLabel = Qt::Label.new('Example) ')
        @fileAddHeadStr = KDE::LineEdit.new do |w|
            w.connect(SIGNAL('textChanged(const QString&)')) do |t| updateSampleFileName end
        end
        @fileAddMediaName = Qt::CheckBox.new(i18n('Add media name'))
        @fileAddChannelName = Qt::CheckBox.new(i18n('Add channel name'))
        @fileAddGenreName = Qt::CheckBox.new(i18n('Add genre name'))

        [ @fileAddMediaName, @fileAddChannelName, @fileAddGenreName ].each do |w|
            w.connect(SIGNAL('stateChanged(int)')) do |s| updateSampleFileName end
        end
        @leaveRawFile = Qt::CheckBox.new(i18n('Leave raw file.(don\'t delete it)'))

        # set objectNames
        #  'kcfg_' + class Settings's instance name.
        @rawFileDirLine.objectName = 'kcfg_rawDownloadDir'
        @downloadDirLine.objectName = 'kcfg_downloadDir'
        @dirAddMediaName.objectName = 'kcfg_dirAddMediaName'
        @dirAddChannelName.objectName = 'kcfg_dirAddChannelName'
        @dirAddGenreName.objectName = 'kcfg_dirAddGenreName'
        @fileAddHeadStr.objectName = 'kcfg_fileAddHeadStr'
        @fileAddMediaName.objectName = 'kcfg_fileAddMediaName'
        @fileAddChannelName.objectName = 'kcfg_fileAddChannelName'
        @fileAddGenreName.objectName = 'kcfg_fileAddGenreName'
        @leaveRawFile.objectName = 'kcfg_leaveRawFile'


        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(Qt::Label.new(i18n('Download Directory')))
            l.addWidgets('  ', @downloadDirLine)
            l.addWidget(Qt::Label.new(i18n('Temporary Raw File Download Directory')))
            l.addWidgets('  ', @rawFileDirLine)
            l.addWidget(Qt::GroupBox.new(i18n('Generating directory')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@dirSampleLabel)
                                vb.addWidget(@dirAddMediaName)
#                                 vb.addWidget(@dirAddChannelName)
                                vb.addWidget(@dirAddGenreName)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Generating file name')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@fileSampleLabel)
                                vb.addWidgets(i18n('Head Text'), @fileAddHeadStr)
                                vb.addWidget(@fileAddMediaName)
#                                 vb.addWidget(@fileAddChannelName)
                                vb.addWidget(@fileAddGenreName)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(@leaveRawFile)
            l.addStretch
        end

        setLayout(lo)
    end

    def updateSampleFileName
        @fileSampleLabel.text = 'Example) ' + getSampleFileName
    end

    def checkState(checkBox)
        checkBox.checkState== Qt::Checked
    end

    def getSampleFileName
        head = @fileAddHeadStr.text
        head += 'Radio ' if checkState(@fileAddMediaName)
        head += 'Radio 7 ' if checkState(@fileAddChannelName)
        head += 'Drama '  if checkState(@fileAddGenreName)
        head += "- " unless head.empty?
        baseName = head  + 'Space Hacks Lost in Space Ship.mp3'
        baseName.gsub(%r{[\/]}, '-')
    end


    def updateSampleDirName
        @dirSampleLabel.text = 'Example) ... /' + getSampleDirName
    end

    def getSampleDirName
        dir = []
        dir << 'Radio' if checkState(@dirAddMediaName)
        dir << 'Radio 7' if checkState(@dirAddChannelName)
        dir << 'Drama' if checkState(@dirAddGenreName)
        File.join(dir.compact)
    end

end

#--------------------------------------------------------------------------
#
#
class PlayerSettingsPage < Qt::Widget
    def initialize(parent=nil)
        super(parent)
        createWidget
    end

    protected

    def createWidget
        @SelectWebPlayerDlg = SelectWebPlayerDlg.new(self)
        @SelectDirectPlayerDlg = SelectDirectPlayerDlg.new(self)
        IRecSettings.instance.regConverter(@SelectWebPlayerDlg, @SelectDirectPlayerDlg)
        puts "web player:" + IRecSettings.webPlayerCommand.to_s
        puts "direct player:" +  IRecSettings.directPlayerCommand.to_s

        @playerTypeSmall = Qt::RadioButton.new(i18n('small iplayer'))
        @playerTypeBeta = Qt::RadioButton.new(i18n('beta iplayer'))

        @innerPlayer = Qt::RadioButton.new(i18n('inner Player'))
        @webPlayer = Qt::RadioButton.new(i18n('Web Player'))
        @directPlayer = Qt::RadioButton.new(i18n('Direnct Stream Player'))

        @webPlayerName = KDE::PushButton.new('Web Player')
        @webPlayerName.connect(SIGNAL(:pressed)) do
            if @SelectWebPlayerDlg.exec == Qt::Dialog::Accepted then
                @webPlayerName.text = @SelectWebPlayerDlg.name
                @webPlayer.checked = true
            end
        end
        @webPlayerName.setProperty("kcfg_property", Qt::Variant.new("text"))

        @directPlayerName = KDE::PushButton.new('Direct Player')
        @directPlayerName.connect(SIGNAL(:pressed)) do
            if @SelectDirectPlayerDlg.exec == Qt::Dialog::Accepted then
                @directPlayerName.text = @SelectDirectPlayerDlg.name
                @directPlayer.checked = true
            end
        end
        @directPlayerName.setProperty("kcfg_property", Qt::Variant.new("text"))

        # set objectNames
        #  'kcfg_' + class Settings's instance name.
        @playerTypeSmall.objectName = 'kcfg_playerTypeSmall'
        @playerTypeBeta.objectName = 'kcfg_playerTypeBeta'
        @innerPlayer.objectName = 'kcfg_useInnerPlayer'
        @webPlayer.objectName = 'kcfg_useWebPlayer'
        @directPlayer.objectName = 'kcfg_useDirectPlayer'
        @webPlayerName.objectName = 'kcfg_webPlayerName'
        @directPlayerName.objectName = 'kcfg_directPlayerName'


        # layout
        lo = Qt::VBoxLayout.new do |l|
            l.addWidget(Qt::GroupBox.new(i18n('iPlayer Type')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@playerTypeSmall)
                                vb.addWidget(@playerTypeBeta)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Player')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@innerPlayer)
                                vb.addWidget(@webPlayer)
                                vb.addWidgets('  ', @webPlayerName, nil)
                                vb.addWidget(@directPlayer)
                                vb.addWidgets('  ', @directPlayerName, nil)
                            end
                            g.setLayout(vbx)
                       end
                       )
            l.addStretch
        end

        setLayout(lo)
    end
end
