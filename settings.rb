#
#    2007 by ruby.twiddler@gmail.com
#
require 'kio'


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
        @dirAddMediaName = Qt::CheckBox.new(i18n('Add media name'))
        @dirAddChannelName = Qt::CheckBox.new(i18n('Add channel name'))
        @dirAddGenreName = Qt::CheckBox.new(i18n('Add genre name'))
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
            l.addLayout(Qt::HBoxLayout.new do |hl|
                            hl.addWidget(Qt::Label.new('  '))
                            hl.addWidget(@downloadDirLine)
                        end
                        )
            l.addWidget(Qt::Label.new(i18n('Temporary Raw File Download Directory')))
            l.addLayout(Qt::HBoxLayout.new do |hl|
                            hl.addWidget(Qt::Label.new('  '))
                            hl.addWidget(@rawFileDirLine)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Generating directory name')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@dirSampleLabel)
                                vb.addWidget(@dirAddMediaName)
                                vb.addWidget(@dirAddChannelName)
                                vb.addWidget(@dirAddGenreName)
                            end
                            g.setLayout(vbx)
                        end
                        )
            l.addWidget(Qt::GroupBox.new(i18n('Generating file name')) do |g|
                            vbx = Qt::VBoxLayout.new do |vb|
                                vb.addWidget(@fileSampleLabel)
                                hbx = Qt::HBoxLayout.new do |hb|
                                    hb.addWidget(Qt::Label.new(i18n('Head Text')))
                                    hb.addWidget(@fileAddHeadStr)
                                end
                                vb.addLayout(hbx)
                                vb.addWidget(@fileAddMediaName)
                                vb.addWidget(@fileAddChannelName)
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
        @playerTypeSmall = Qt::RadioButton.new(i18n('small iplayer'))
        @playerTypeBeta = Qt::RadioButton.new(i18n('beta iplayer'))

        # set objectNames
        #  'kcfg_' + class Settings's instance name.
        @playerTypeSmall.objectName = 'kcfg_playerTypeSmall'
        @playerTypeBeta.objectName = 'kcfg_playerTypeBeta'


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
            l.addStretch
        end

        setLayout(lo)
    end
end
