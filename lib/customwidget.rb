require 'Qt'

class LabledRangeWidget < Qt::Widget
    def initialize(labels, startPos=0, endPos=0)
        super()
        @labels = labels
        @movePos = nil

        w = h = 12
        @labelWidths = @labels.map do |label|
            lrect = fontMetrics.boundingRect(label)
            w = [w, lrect.width].max
            h = [h, lrect.height].max
            lrect.width
        end
        @charWidth = w
        @charHeight = h

        @margin = 4
        x = 0
        @labelsXPos = @labelWidths.map do |w|
            x += w + @margin*2
        end
        @labelsXPos.unshift(0)

        self.minimumWidth = @labelsXPos[-1]+1
        self.minimumHeight = @charHeight + @margin*2

        setRange(startPos, endPos)
    end

    def setRange(startPos, endPos)
        n = @labels.size
        startPos = [startPos, n].min
        endPos = [endPos, n].min
        if startPos < endPos then
            @startPos = startPos
            @endPos = endPos
        else
            @startPos = endPos
            @endPos = startPos
        end
        update
    end


    def paintEvent(event)
        painter = Qt::Painter.new(self)

        if @movePos then
            x0, x1 = @movePos, @stopPos
            x0, x1 = x1, x0 if x0 > x1     # swap
            w = @labelWidths[x0..x1].inject(:+) + (x1-x0+1)*(@margin*2)
            roundRect = Qt::Rect.new( @labelsXPos[x0], 0,
                w, @charHeight + @margin*2-1 )
        else
            w = @labelWidths[@startPos..@endPos].inject(:+) + \
                    (@endPos-@startPos+1)*(@margin*2)
            roundRect = Qt::Rect.new( @labelsXPos[@startPos], 0,
                w, @charHeight + @margin*2-1 )
        end
        roundRadus = @charHeight/2
        painter.drawRoundedRect( roundRect, roundRadus, roundRadus )
        0.upto(@labels.size-1).each do |i|
            painter.drawText(@labelsXPos[i]+@margin, @margin, @labelWidths[i], @charHeight, \
                             Qt::AlignHCenter | Qt::AlignCenter, @labels[i])
        end

        painter.end
    end

    def mousePressEvent(event)
        return unless event.button == Qt::LeftButton
        index = getIndex(event.pos)
        return unless index
        if index > (@startPos + @endPos)/2 then
            @movePos, @stopPos = index, @startPos
        else
            @movePos, @stopPos = index, @endPos
        end
        update
    end

    def mouseMoveEvent(event)
        return unless (event.buttons & Qt::LeftButton.to_i) && @movePos

        index = getIndex(event.pos)
        return unless index
        if index != @movePos then
            @movePos = index
            update
        end
    end

    def mouseReleaseEvent(event)
        return unless event.button == Qt::LeftButton && @movePos

        if @movePos <= @stopPos then
            @startPos, @endPos = @movePos, @stopPos
        else
            @startPos, @endPos = @stopPos, @movePos
        end
        @movePos = nil
        update
    end

    def getIndex(pos)
        return nil if pos.x < 0
        x = pos.x
        i = 0
        @labelsXPos[1..-1].each do |lx|
            return i if x < lx
            i += 1
        end
        nil
    end
end
