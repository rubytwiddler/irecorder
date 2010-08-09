def e1(&block)
    block.call('a')
end

def e2( &block)
    e1( &block)
end

e2 { |i| puts i }