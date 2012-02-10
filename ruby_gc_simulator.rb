

module Slide
  def slide! title, body = nil
    puts "!SLIDE"
    puts "h1. #{title}"
    puts ""
    puts body
    puts ""
  end

  def render! msg = nil
    slide! msg, <<"END"
!IMAGE BEGIN DOT
#{Renderer.new(mem, msg).render!}
!IMAGE END
END
  end

  extend self
end

class Memory
  include Slide; def mem; self; end
  attr_accessor :mark_bits

  def initialize x, *roots
    super()
    @binding = x
    @roots = [ ]
    @objects = { }
    @obj_id = -1
    roots.each { | r | add_root! r }
  end

  def mark_bits!
    @mark_bits = MarkBits.new(@obj_id)
    self
  end

  def add_root! r
    @roots << Root.new(r)
    self
  end

  def roots
    e = Roots.new
    @roots.each do | r |
      e[r] = eval(r.to_s, @binding)
    end
    # $stderr.puts " e = #{e.inspect}"
    e
  end

  def add_object! x
    @objects[x.object_id] ||= [ x, false, @obj_id += 1 ]
  end
  def free_object! x
    x = @objects[x.object_id] and x[0] = nil
  end
  def objects
    @objects.values.sort_by{|x| x[2]}.map{|x| x.first}
  end
  def obj_id x
    x = @objects[x.object_id] and x[2]
  end
  def marked? x
    x = @objects[x.object_id] and x[1]
  end
  def clear_mark! x
    add_object!(x)[1] = false
    @mark_bits[obj_id(x)] = false if @mark_bits
  end
  def set_mark! x
    add_object!(x)[1] = true
    @mark_bits[obj_id(x)] = true if @mark_bits
  end

  def eval! expr, title = nil, *opts
    unless opts.include?(:no_slide)
      slide! title, <<"END"

@@@ ruby

#{expr}

@@@
END
    end
    if before = opts.include?(:before)
      render! "#{title} : Before"
    end
    eval(expr, @binding)
    render! "#{title}#{before ? ' : After ' : nil}"
  end
end

class Roots < Hash; end
class MarkBits < Array; end

class Root
  def initialize x
    @name = x
  end
  def inspect
    @name.inspect
  end
  def to_s
    @name.to_s
  end
end

class Collector
  include Slide
  attr_reader :mem
  def initialize mem
    @mem = mem
  end

  def collect!
    mark_roots!
    sweep!
  end

  def mark_roots! msg = "Mark roots"
    render! "GC: #{msg}"
    mem.roots.each do | k, v |
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
      render! "GC: Mark #{x.class}@#{mem.obj_id(x)}"
      case x
      when Array
        x.each { | e | mark!(e) }
      when Hash
        x.each { | k, v | mark!(k); mark!(v) }
      else
        x.instance_variables.each { | v | mark!(x.instance_variable_get(v)) }
      end
    end
  end

  def sweep!
    render! "GC: Before Sweep"
    obj_id = -1
    mem.objects.each do | x |
      next if x.nil?
      name = "#{x.class}@#{obj_id += 1}"
      if mem.marked?(x)
        name << " : unmark"
        mem.clear_mark!(x)
      else
        name << " : free"
        mem.free_object!(x)
      end
      @highlight_memory_obj_id = obj_id
      render! "GC: Sweep #{name}"
    end
    render! "GC: After Sweep"
    self
  end
end

ATOMS = [ nil, true, false, Fixnum, Symbol, Roots, Root, Memory ]

class Renderer
  def initialize mem = nil, title = nil
    @title = title
    mem!(mem) if mem
  end

  def clear!
    @id = @port = 0
    @node_out = ''
    @edge_out = ''
    @node_id = { }
    @visited = { }
    self
  end

  def mem! x
    @mem = x
    @roots = @mem.roots
    clear!
    @rank = 1; node(@mem);
    @rank = 1; node(@mem.mark_bits)
    @rank = 2; node(@roots);
    clear!
    @rank = 1; node(@mem);
    @rank = 1; node(@mem.mark_bits)
    @mem.objects.each { | x | node(x) }
    @rank = 2; node(@roots);
    self
  end

  def node_id x
    @node_id[x.object_id] ||= "node#{x.object_id}".inspect
  end

  def node x
    return if x.nil?
    return if @visited[x.object_id]
    @visited[x.object_id] = x
    style = ''
    td_style = ''

    added = false
    show_mark = true
    case x
    when Roots, MarkBits
      show_mark = false
      style << 'style = "dotted"'
    when Memory
      show_mark = false
      style << 'style = "dotted", pos = "0,0!" '
    when *ATOMS
    else
      @mem.add_object!(x)
      added = true
    end

    nodes = [ ]

    name = "#{x.class}"
    if added and obj_id = @mem.obj_id(x)
      name << "@#{obj_id}"
    end
    mark = @mem.marked?(x)
    td_style << (mark ? 'BGCOLOR="black" COLOR="white"' : '')

    rank = nil
=begin
    if @rank
      rank = %Q{rank = #{@rank}}
      @rank = nil
    end
=end

    @node_out << %Q{#{node_id(x)} [
  shape = "none"
  #{style}
  label=<
  <TABLE>
    <TR><TD COLSPAN="2" ALIGN="LEFT" PORT="-1">#{name}</TD></TR>
}
    if show_mark && ! @mem.mark_bits
      @node_out << %Q{    <TR><TD COLSPAN="2" ALIGN="CENTER" PORT="mark" #{td_style}>#{mark ? "MARK" : "____"}</TD></TR>
}
    end

    case x
    when nil, true, false, Numeric, Symbol, String
      @node_out << %Q{<TR><TD COLSPAN="2" ALIGN="LEFT">#{x.inspect}</TD></TR>}
    when Memory
      x.objects.each { | e | nodes << slot(x, e, :edge_style => 'style = "dashed"') }
    when MarkBits
      x.each { | e | nodes << slot(x, e ? "MARK" : "____", :inspect => false, :node => false) }
    when Array
      x.each { | e | nodes << slot(x, e) }
    when Hash
      x.keys.sort_by{|k| k.to_s}.each do | k |
        v = x[k]
        nodes << slot(x, v, :key => k)
      end
    else
      x.instance_variables.each { | k | nodes << slot(x, x.instance_variable_get(k), :key => k) }
    end
    @node_out << %Q{
  </TABLE>
  >
];
}
    nodes.each { | e | node(e) if e }
    self
  end

  def slot x, v, opts = { }
    use_k = opts.key?(:key)
    k = opts[:key]
    edge_style = opts[:edge_style]
    @node_out << %Q{    <TR>}
    if use_k
      @node_out << %Q{<TD ALIGN="RIGHT" PORT="#{@port += 1}">#{k.inspect}</TD><TD}
    else
      @node_out << %Q{<TD COLSPAN="2"}
    end
    @node_out << %Q{ ALIGN="LEFT" PORT="#{@port += 1}">}
    case v
    when nil, true, false, Fixnum, Symbol
      v = v.inspect unless opts[:inspect] == false
      @node_out << "#{v}"
      v = nil
    else
      if opts[:node] == false
        v = v.inspect unless opts[:inspect] == false
        @node_out << "#{v}"
        v = nil
      else
        @node_out << "..."
      end
    end
    @node_out << %Q{</TD></TR>\n}
    if v
      @edge_out << %Q{#{node_id(x)}:#{@port.to_s.inspect}:e -> #{node_id(v)}:"-1":w [ #{edge_style} ];\n}
    end
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
    # return self
    @@file_id ||= 0
    @@file_id += 1
    @file_id = "%03d" % @@file_id
    @file_gv = "sim#{@file_id}.gv"
    @file_svg = @file_gv.sub(/\.gv$/, '.svg')
    File.open(@file_gv, "w+") do | fh |
      fh.write self.to_s
    end
    # system("dot #{@file_gv.inspect} > #{(@file_gv + '.gv').inspect}")
    # system("dot -Tsvg #{@file_gv.inspect} > #{@file_svg.inspect}")
    # system("open #{@file_svg.inspect}")
    self
  end

end

Slide.slide! "CRuby GC", <<'END'
* Kurt Stephens
* Enova Financial
* 2012/02/10
* Code: http://github.com/kstephens/ruby_gc_simulator
* Slides: http://kurtstephens.com/pub/ruby/ruby_gc_simulator/ruby_gc_simulator/
END

Slide.slide! "Mark and Sweep", <<'END'
h2. Mark
* Starting with Roots,
* Mark each referenced object, if unmarked,
* Recursively.

h2. Sweep
* For all objects in memory:
** Free unmarked objects.
** Unmark marked objects.
END

Slide.slide! "Roots", <<'END'
* Global Namespace : Kernel, Object
* Global Variables and CONSTANTS : $:, ARGV
* Local Variables : binding, caller
* self, &block
* Internals: rb_global_variable(), VALUEs on C stack.
END

mem = Memory.new(binding, :x, :y)

mem.eval! <<'END', 'Initial Object Graph'
x = [ 0, 1, "two", "three", :four, 3.14159, 123456781234567812345678 ]
y = { :a => 1, :b => "bee" }
x << y
END

mem.eval! <<'END', 'Remove reference to "three"', :before
x[3] = nil
END

Collector.new(mem).collect!

mem.eval! <<'END', 'Remove References to Hash', :before
y = x[-1] = nil
END

Collector.new(mem).collect!

Slide.slide! "3.times { x.pop } ", <<'END'
@@@ ruby

x.pop; x.pop; x.pop

@@@
END

3.times do
  mem.eval! <<'END', 'x.pop', :no_slide
x.pop
END
end

Collector.new(mem).collect!

Slide.slide! "Mark And Sweep Is Expensive", <<'END'
* Every object is read.
* Every mark bit is read and mutated.
* Even if most of objects are not garbage (Modules => Methods & CONSTANTS).
END

Slide.slide! "Coding Styles affect GC", <<'END'
* Every evaluated String, Float, String literal creates a new object.
* Shared String buffers reduce memory usage, but do not improve GC times.
* Every Float, Bignum math operation creates a new Object.
* Use String#<<, not String#+.
END

Slide.slide! "Mark bits", <<'END'
h2. Copy-On-Write pages after process fork().

* CRuby <2.0
** Mark bits are at the head of each object.
* REE, CRuby 2.0 (HEAD)
** Mark bits are stored in external arrays.
** Slower.
END

mem.mark_bits!
Collector.new(mem).mark_roots!("With Mark Bits")

Slide.slide! "JRuby, Rubinius", <<'END'
* Rubinius has multiple colectors.
* JVM Collectors are highly-tuned.
* Some Commercial JVMS have *very* performant collectors.
END

Slide.slide! "Other GC", <<'END'
* Parallel Sweep - not seen yet.
* Parallel Mark - prototype presented at RubyConf 2011.
* Lazy Sweep - already in CRuby
* N-color marking
** Tredmill - https://github.com/kstephens/tredmill
** Needs Write Barrier
* Generational - difficult, unlikely.
** Needs Write Barrier
END

Slide.slide! "CRuby GC Options", <<'END'
h2. mem_api - http://github.com/kstephens/ruby
* Runtime hooks for different GCs/memory systems.
* Malloc-only
* Core
* BDW
* SMAL - http://github.com/kstephens/smal
END

Slide.slide! "Weak References", <<'END'
* JRuby
** Weak References, Soft References, Reference Queues.
* Rubinius.
** Weak References
* CRuby - not well supported.
** ref: http://github.com/kstephens/ref - Weak, Soft, RefQueues
END

Slide.slide! "Generational GC", <<'END'
* Youngest objects are likely to be garbage.
* Younger objects are likely refer to older objects.
* Older objects are less likely to change or point to younger objects.
END

Slide.slide! "Generational GC Is Hard", <<'END'
* Write Barrier needed to keep track of changes to older or already marked objects.
* Need to keep track of references from older generations to new generations.
* CRuby API makes write barrier difficult.
* Lua handles this by never exposing objects directly; stack only.
END

Slide.slide! "Questions", <<'END'
END

