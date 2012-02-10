

module RenderMem
  def slide! title, body = nil
    puts "!SLIDE"
    puts "h1. #{title}"
    puts ""
    puts body
    puts ""
    end
  end

  def render! msg = nil
    slide! msg, <<"END"
!IMAGE BEGIN DOT
#{Renderer.new(mem, msg).render!}"
!IMAGE END
END
  end
end

class Memory
  include RenderMem; def mem; self; end

  def initialize x, *roots
    super()
    @binding = x
    @roots = [ ]
    @objects = { }
    @obj_id = 0
    roots.each { | r | add_root! r }
  end

  def add_root! r
    @roots << Root.new(r)
    self
  end

  def environment
    e = Environment.new
    @roots.each do | r |
      e[r] = eval(r.inspect, @binding)
    end
    # $stderr.puts " e = #{e.inspect}"
    e
  end

  def add_object! x
    @objects[x.object_id] ||= [ x, false, @obj_id += 1 ]
  end
  def free_object! x
    @objects.delete(x.object_id)
  end
  def objects
    @objects.values.map{|x| x.first}
  end
  def obj_id x
    x = @objects[x.object_id] and x[2]
  end
  def marked? x
    x = @objects[x.object_id] and x[1]
  end
  def clear_mark! x
    add_object!(x)[1] = false
  end
  def set_mark! x
    add_object!(x)[1] = true
  end

  def eval! expr, title = nil
    eval(expr, @binding)
    render! title, <<"END"

@@@ ruby

#{expr}

@@@
END
  end
end

class Environment < Hash; end

class Root
  def initialize x
    @name = x
  end
  def inspect
    @name.to_s
  end
end

class Collector
  include RenderMem
  attr_reader :mem
  def initialize mem
    @mem = mem
  end

  def collect!
    render! "Before mark roots"
    mark_roots!
    render! "After mark roots"
    sweep!
    render! "After Sweep"
  end

  def mark_roots!
    mem.environment.each do | k, v |
      mark!(v)
    end
  end

  def mark! x
    case x
    when *ATOMS
      return
    end
    unless mem.marked?(x)
      mem.set_mark!(x)
      render! "Mark #{x.class}@#{mem.obj_id(x)}"
      case x
      when Array
        x.each { | e | mark!(e) }
      when Hash
        x.each { | k, v | mark!(k); mark!(e) }
      else
        x.instance_variables.each { | v | mark!(x.instance_variable_get(v)) }
      end
    end
  end

  def sweep!
    mem.objects.each do | x |
      if mem.marked?(x)
        mem.clear_mark!(x)
      else
        mem.free_object!(x)
      end
    end
  end
end

ATOMS = [ nil, true, false, Fixnum, Symbol, Environment ]

class Renderer
  def initialize mem = nil, title = nil
    @title = title
    mem!(mem) if mem
  end

  def mem! x
    @mem = x
    @id = @port = 0
    @node_out = ''
    @edge_out = ''
    @node_id = { }
    @visited = { }
    @root = x
    @env = @mem.environment
    node(@env)
    @mem.objects.each { | x | node(x) }
    self
  end

  def node_id x
    @node_id[x.object_id] ||= "node#{x.object_id}".inspect
  end

  def node x
    return if @visited[x.object_id]
    @visited[x.object_id] = x

    case x
    when *ATOMS 
    else
      @mem.add_object!(x) if @mem
    end

    nodes = [ ]

    name = "#{x.class}"
    if obj_id = @mem.obj_id(x)
      name << "@#{obj_id}"
    end
    style = @mem.marked?(x) ? :'BGCOLOR="black" COLOR="white"' : nil

    @node_out << %Q{#{node_id(x)} [
  shape = "none"
  label=<
  <TABLE>
    <TR><TD #{style} COLSPAN="2" ALIGN="LEFT" PORT="-1">#{name}</TD></TR>
}


    case x
    when nil, true, false, Numeric, Symbol, String
      @node_out << %Q{<TR><TD COLSPAN="2" ALIGN="LEFT">#{x.inspect}</TD></TR>}
    when Array
      x.each { | e | nodes << slot(x, e) }
    when Hash
      x.each { | k, v | nodes << slot(x, v, k, true) }
    else
      x.instance_variables.each { | k | nodes << slot(x, x.instance_variable_get(k), k, true) }
    end
    @node_out << %Q{
  </TABLE>
  >
];
}
    nodes.each { | e | node(e) if e }
    self
  end

  def slot x, v, k = nil, use_k = nil
    @node_out << %Q{    <TR>}
    if use_k
      @node_out << %Q{<TD ALIGN="RIGHT" PORT="#{@port += 1}">#{k.inspect}</TD><TD}
    else
      @node_out << %Q{<TD COLSPAN="2"}
    end
    @node_out << %Q{ ALIGN="LEFT" PORT="#{@port += 1}">}
    case v
    when nil, true, false, Fixnum, Symbol
      @node_out << "#{v.inspect}"
      v = nil
    else
      @node_out << "..."
      @edge_out << %Q{#{node_id(x)}:#{@port.to_s.inspect}:e -> #{node_id(v)}:"-1":w [ ];\n}
    end
    @node_out << %Q{</TD></TR>\n}
    v
  end

  def to_s
    @to_s ||=
      "digraph #{(@title || 'unknown').inspect} {" << '
  graph [
    rankdir = "LR"
  ];
  node [
    fontsize = "12"
    shape = "record"
  ];
  edge [
  ];
' << @node_out << @edge_out << "}\n"
  end

  def render!
    @@file_id ||= 0
    @@file_id += 1
    @file_id = "%03d" % @@file_id
    @file_gv = "sim#{@file_id}.gv"
    @file_svg = "sim#{@file_id}.svg"
    File.open(@file_gv, "w+") do | fh |
      fh.write self.to_s
    end
    system("dot -Tsvg #{@file_gv.inspect} > #{@file_svg.inspect}")
    system("open #{@file_svg.inspect}")
    self
  end

end

mem = Memory.new(binding, :x, :y)
mem.eval! <<'END', 'Initial Object Graph'
x = [ 1, 2, "three", :four, 3.14159, 123456781234567812345678 ]
y = { :a => 1, :b => "bee" }
x << y
END

mem.eval! <<'END', 'Remove References to y'
y = x[-1] = nil
END

Collector.new(mem).collect!
