require 'fileutils'

require "bbcnet.rb"

#-------------------------------------------------------------------
#
#
#
class DownloadProcess < Qt::Process
    slots   'taskFinished(int,QProcess::ExitStatus)'
    attr_reader     :sourceUrl, :fileName
    attr_accessor   :taskItem

    #
    DEBUG_DOWNLOAD = false

    # @stage
    DOWNLOAD = 0
    CONVERT = 1
    FINISHED = 2

    # @status
    INITIAL = 0
    RUNNING = 1
    ERROR = 2
    DONE = 3
    def statusMessage
        case @status
        when INITIAL, RUNNING, DONE
            %w{ Downloading Converting Finished }[@stage]
        when ERROR
            "Error : " + %w{ Download Convert Finish }[@stage]
        else
            "???"
        end
    end

    def status=(st)
        @status = st
        @taskItem.status = statusMessage if @taskItem
        $log.misc { "status:#{status}" }
    end

    #--------------------------
    # check status
    def running?
        @status == RUNNING
    end

    def error?
        @status == ERROR
    end

    #--------------------------
    # check stage
    def finished?
        @stage == FINISHED
    end

    def rawDownloaded?
        @stage >= CONVERT
    end

    class Command
        attr_accessor   :app, :args, :msg
        def initialize(app, args, msg)
            @app = app
            @args = args
            @msg = msg
        end
    end

    attr_reader :sourceUrl, :rawFileName
    attr_reader :rawFilePath, :outFilePath

    def initialize(parent, metaInfo, fName)
        super(parent)
        @metaInfo = metaInfo
        @parent = parent
        @taskItem = nil
        @startTime = Time.new
        @sourceUrl = @metaInfo.wma.url
        @rawFileName = fName
        @rawFilePath = File.join(IRecSettings.rawDownloadDir.path, fName)
        mkdirSavePath(@rawFilePath)
        @outFileName = @rawFileName.gsub(/\.\w+$/i, '.mp3')
        @outFilePath = File.join(IRecSettings.downloadDir.path, @outFileName)
        mkdirSavePath(@outFilePath)
        $log.debug { "@rawFilePath : #{@rawFilePath }" }
        $log.debug { "@outFilePath : #{@outFilePath}" }

        @stage = DOWNLOAD
        @status = INITIAL

        connect(self, SIGNAL('finished(int,QProcess::ExitStatus)'), self, SLOT('taskFinished(int,QProcess::ExitStatus)') )
    end


    def beginTask
        # 1st stage : download
        if File.exist?(@rawFilePath) then
            @stage = DOWNLOAD
            @downNG = true
            self.status = RUNNING
            @currentCommand = makeMPlayerDownloadCmd
            taskFinished(1,0)
#             @stage = CONVERT
#             @outFileName = @rawFileName.gsub(/\.\w+$/i, '.mp3')
#             @outFilePath = File.join(IRecSettings.downloadDir.path, @outFileName)
            $log.debug { "@rawFilePath duration:" + AudioFile.getDuration(@rawFilePath).to_s }
            $log.debug { "@outFilePath duration:" + AudioFile.getDuration(@outFilePath).to_s }
            $log.debug { "metainf duration:" + @metaInfo.duration.to_s }
#             if File.exist?(@outFilePath) then
#                 taskFinished(1,0)
#             else
#                 $log.debug { "begin convert" }
#                 beginConvert
#                 return
#             end
        else
            beginDownload
        end

#         beginDownload
    end


    def retryTask
        $log.debug { "retry! in main." }
        if error? then
            # retry
            case @stage
            when DOWNLOAD
                @startTime = Time.new
                beginDownload
            when CONVERT
                @startTime = Time.new
                beginConvert
            end
        else
            $log.warn { "cannot retry the successfully finished or running process." }
        end
    end

    def cancelTask
        if running? then
            self.terminate
        end
    end

    def removeData
        if running? then
            self.terminate
        end
        begin
            File.delete(@rawFilePath)
            File.delete(@outFilePath)
        rescue => e
            $log.info { e }
        end
    end

    def updateLapse
        taskItem.updateTime(lapse)
    end

    def lapse
        Time.now - @startTime
    end

    # slot :
    def taskFinished(exitCode, exitStatus)
        checkReadOutput
        if (exitCode.to_i.nonzero? || exitStatus.to_i.nonzero?) && checkErroredStatus then
            self.status = ERROR
            $log.error { [ makeErrorMsg, "exitCode=#{exitCode}, exitStatus=#{exitStatus}" ] }
        else
            $log.info {
                [ "Successed to download a File '%#2$s'",
                    "Successed to convert a File '%#2$s'", ][@stage] %
                [ @sourceUrl, @rawFilePath ]
            }
            nextTask
        end
    end

    def updateView
        if running? then
            # update Lapse time
            updateLapse

            # dump IO message buffer
            checkReadOutput
        end
    end


    protected
    # increment stage
    def nextTask
        @stage += 1
        case @stage
        when DOWNLOAD
            beginDownload
        when CONVERT
            beginConvert
        else
            removeRawFile
            allTaskFinished
        end
    end

    def beginDownload
        $log.info { " DownloadProcess : beginDownload." }
        @stage = DOWNLOAD
        @downNG = true
        self.status = RUNNING
        @currentCommand = makeMPlayerDownloadCmd

        $log.info { @currentCommand.msg }
        start(@currentCommand.app, @currentCommand.args)
    end

    def makeMPlayerDownloadCmd
        # make MPlayer Downlaod comand
        cmdMsg = "mplayer -noframedrop -dumpfile %s -dumpstream %s" %
                    [@rawFilePath.shellescape, @sourceUrl.shellescape]
        cmdApp = "mplayer"
        cmdArgs = ['-noframedrop', '-dumpfile', @rawFilePath, '-dumpstream', @sourceUrl]

        # debug code.
        if DEBUG_DOWNLOAD then
            if rand > 0.4 then
                cmdApp = "test/sleepjob.rb"
                cmdArgs = %w{ touch a/b/ }
            else
                cmdApp = "test/sleepjob.rb"
                cmdArgs = %w{ touch } << @rawFilePath.shellescape
            end
        end

        Command.new( cmdApp, cmdArgs, cmdMsg )
    end

    def beginConvert
        @stage = CONVERT
        self.status = RUNNING

        cmdMsg = "nice -n 19 ffmpeg -i %s -f mp3 %s" %
                    [ @rawFilePath.shellescape, @outFilePath.shellescape]
        cmdApp = "nice"
        cmdArgs = [ '-n', '19', 'ffmpeg', '-i', @rawFilePath, '-f', 'mp3', @outFilePath ]


        # debug code.
        if DEBUG_DOWNLOAD then
            if rand > 0.4 then
                cmdApp = "test/sleepjob.rb"
                cmdArgs = %w{ touch a/b/ }
            else
                cmdApp = "test/sleepjob.rb"
                cmdArgs = %w{ cp -f } + [ @rawFilePath.shellescape, @outFilePath.shellescape ]
            end
        end

        @currentCommand = Command.new( cmdApp, cmdArgs, cmdMsg )
        $log.info { @currentCommand.msg }
        start(@currentCommand.app, @currentCommand.args)
    end


    def removeRawFile
        unless IRecSettings.leaveRawFile then
            begin
                File.delete(@rawFilePath)
            rescue => e
                $log.error { e }
            end
        end
    end

    def checkOutput(msg)
        msgSum = msg.join(' ')
        @downNG &&= false if msgSum =~ /Everything done/i
    end

    # check and read output
    def checkReadOutput
        msg = readAllStandardOutput.data .reject do |l| l.empty? end
        checkOutput(msg)
        $log.info { msg }
    end

    # return error or not
    def checkErroredStatus
        case @stage
        when DOWNLOAD
            return @downNG unless @downNG
            begin
                $log.debug { "check duration for download." }
                rawDuration = AudioFile.getDuration(@rawFilePath)
                return true if rawDuration < @metaInfo.duration - 100
                $log.debug { "check file size for download." }
                File.size(@rawFilePath) < @metaInfo.duration * 5500
            rescue => e
                $log.warn { e }
                true
            end
        when CONVERT
            begin
                $log.debug { "check duration for convert." }
                AudioFile.getDuration(@outFilePath) < AudioFile.getDuration(@rawFilePath) - 10
            rescue => e
                $log.warn { e }
                true
            end
        else
            true
        end
    end




    protected
    def allTaskFinished
        @stage = FINISHED
        self.status = DONE
    end

    def makeErrorMsg
        [ "Failed to download a File '%#2$s'",
            "Failed to convert a File '%#2$s'", ][@stage] %
            [ @sourceUrl, @rawFilePath ]
    end


    def mkdirSavePath(fName)
        dir = File.dirname(fName)
        unless File.exist? dir
            $log.info{ "mkdir : " +  dir }
            FileUtils.mkdir_p(dir)
        end
    end
end


