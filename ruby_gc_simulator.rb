

module Slide
  def slide! title, body, opts = nil
    opts ||= { }
    puts "!SLIDE"
    puts "h1. #{title}"
    puts ""
    puts body
    puts ""
    if opts[:graph]
      puts <<"END"
!IMAGE BEGIN DOT
#{Renderer.new(mem, title, opts).render!}
!IMAGE END
END
    end
  end

  def render! title = nil, opts = nil
    opts ||= { }
    slide! title, <<"END", opts
!IMAGE BEGIN DOT
#{Renderer.new(mem, title, opts).render!}
!IMAGE END
END
  end

  extend self
end

class Memory
  include Slide; def mem; self; end
  attr_accessor :free_list, :mark_bits

  def initialize x, *roots
    super()
    @binding = x
    @roots = [ ]
    @slots = [ ]
    @object_map = { }
    @free_list = FreeList.new
    @obj_id = -1
    roots.each { | r | add_root! r }
  end

  def mark_bits!
    @mark_bits = MarkBits.new(@slots.size)
    self
  end

  def add_root! r
    @roots << Root.new(r)
    self
  end

  def roots
    e = @roots_obj ||= Roots.new
    e.clear
    @roots.each do | r |
      e[r] = eval(r.to_s, @binding)
    end
    # $stderr.puts " e = #{e.inspect}"
    e
  end

  def add_object! x
    # $stderr.puts "add_object!: free_list = #{@free_list.inspect}"
    obj_id = @object_map[x.object_id] ||= (@free_list.pop || (@obj_id += 1))
    slot = @slots[obj_id] ||= [ ]
    slot[0] = x
    slot[1] = obj_id
    # $stderr.puts "  add_object! #{x} => #{slot.inspect}"
    slot
  end
  def slot x
    obj_id = @object_map[x.object_id] and @slots[obj_id]
  end
  def free_object! x
    if x = slot(x)
      @object_map.delete(x[0].object_id)
      @free_list.push(x[1])
      x[0] = nil
      x[2] = false
      # $stderr.puts "  free_object!: free_list = #{@free_list.inspect}"
    end
  end
  def objects
    @slots.map{|x| x.first}
  end
  def obj_id x
    x = slot(x) and x[1]
  end
  def marked? x
    x = slot(x) and x[2]
  end
  def clear_mark! x
    x = slot(x)
    x[2] = false
    @mark_bits[x[1]] = false if @mark_bits
    # $stderr.puts "  UNMARK: slot = #{x.inspect}"
    self
  end
  def set_mark! x
    x = slot(x)
    # $stderr.puts "  MARK: slot = #{x.inspect}"
    x[2] = true
    @mark_bits[x[1]] = true if @mark_bits
    self
  end

  def eval! title, expr, opts = nil
    opts ||= { }
    if opts[:slide] != false
      slide! title, <<"END"

@@@ ruby

#{expr}

@@@
END
    end
    if opts[:before]
      render! "#{title} : Before"
    end
    eval(expr, @binding)
    render! "#{title}#{opts[:before] ? ' : After ' : nil}", opts
  end
end

class Roots < Hash; end
class MarkBits < Array; end
class FreeList < Array; end

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
    roots = mem.roots
    render! "GC: #{msg}", :highlight_objects => [ roots ]
    roots.each do | k, v |
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

ATOMS = [ nil, true, false, Fixnum, Symbol, Roots, Root, Memory, FreeList, MarkBits ]

class Renderer
  def initialize mem = nil, title = nil, opts = nil
    @title = title
    @opts = opts ||= { }
    mem!(mem) if mem
  end

  def clear!
    @port = 0
    @node_out = ''
    @edge_out = ''
    @id = 0
    @node_id = { }
    @visited = { }
    self
  end

  def mem! x
    @mem = x
    @roots = @mem.roots
    clear!
    # $stderr.puts "  #{self.class} #{@title} opts = #{@opts.inspect}\n#{caller * "\n"}\n"
    if @opts[:render_memory] != false
      @rank = 1; node(@mem);
      @rank = 1; node(@mem.mark_bits)
    end
    @rank = 2; node(@roots);
    clear!
    if @opts[:render_memory] != false
      @rank = 1; node(@mem);
      @rank = 1; node(@mem.mark_bits)
      @rank = 1; node(@mem.free_list)
    end
    @rank = 2; node(@roots);
    @mem.objects.each { | x | node(x) }
    self
  end

  def node_id x
    @node_id[x.object_id] ||= "#{x.class}#{@id += 1}".inspect
  end

  def node x
    return if x.nil?
    return if FreeList === x and x.empty?
    return if @visited[x.object_id]
    @visited[x.object_id] = x
    style = ''

    added = false
    show_mark = true
    case x
    when Roots, MarkBits, FreeList, Memory
      show_mark = false
      style << 'style = "dotted"' << "\n"
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

    if ho = @opts[:highlight_objects] and ho.include?(x)
      style << "penwidth = 10\n"
    end

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
      mark = @mem.marked?(x)
      td_style = (mark ? 'BGCOLOR="black" COLOR="white"' : nil)
      @node_out << %Q{    <TR><TD COLSPAN="2" ALIGN="CENTER" PORT="mark" #{td_style}>#{mark ? "MARK" : "----"}</TD></TR>
}
    end

    case x
    when nil, true, false, Numeric, Symbol, String
      @node_out << %Q{<TR><TD COLSPAN="2" ALIGN="LEFT">#{x.inspect}</TD></TR>}
    when Memory
      port = -1
      x.objects.each { | e | nodes << slot(x, e, :port => port += 1, :edge_style => 'style = "dotted", color = "grey"') }
    when MarkBits
      port = -1
      x.each { | e | nodes << slot(x, e ? "MARK" : "----",
                              :style => e ? 'BGCOLOR="black" COLOR="white"' : nil,
                              :port => port += 1,
                              :inspect => false,
                              :node => false) }
    when FreeList
      mem_node_id = node_id(@mem)
      last = %Q{#{node_id(x)}:"-1":e}
      x.reverse.each do | e |
        node = %Q{#{mem_node_id}:"#{e}":w}
        @edge_out << %Q{#{last} -> #{node} [ style = "dashed" ];\n}
        last = node
      end
    when Array
      port = -1
      x.each { | e | nodes << slot(x, e, :port => port += 1) }
    when Hash
      port = -1
      x.keys.sort_by{|k| k.to_s}.each do | k |
        v = x[k]
        nodes << slot(x, v, :key => k, :port => port += 1)
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
    style = opts[:style]
    edge_style = opts[:edge_style]
    port = opts[:port] || (@port += 1)
    @node_out << %Q{    <TR>}
    if use_k
      @node_out << %Q{<TD ALIGN="RIGHT">#{k.inspect}</TD><TD}
    else
      @node_out << %Q{<TD COLSPAN="2"}
    end
    @node_out << %Q{ ALIGN="LEFT" PORT="#{port}" #{style} >}
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
      @edge_out << %Q{#{node_id(x)}:#{port.to_s.inspect}:e -> #{node_id(v)}:"-1":w [ #{edge_style} ];\n}
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
    return self
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

######################################################################

Slide.slide! "CRuby GC", <<'END'
* Kurt Stephens
* Enova Financial
* 2012/02/10
* Code: "":http://github.com/kstephens/ruby_gc_simulator
* Slides: "":http://kurtstephens.com/pub/ruby/ruby_gc_simulator/ruby_gc_simulator/
END

mem2 = Memory.new(binding, :a, :b, :c)

mem2.eval! 'Circular Object Graph', <<'END', :render_memory => false
a = [ nil ]; b = [ a ]; c = [ b ]
a[0] = c; b = c = nil;
END

mem = Memory.new(binding, :x, :y)

mem.eval! 'Initial Object Graph', <<'END', :render_memory => false
x = [ 0, 1, "two", "three", :four, 3.14159, 123456781234567812345678 ]
y = { :a => 1, :b => "bee" }
x << y
END

Slide.slide! "Mark and Sweep", <<'END'
h2. Mark
* Starting with Roots,
* Mark each referenced object, if unmarked,
* Recursively.

h2. Sweep
* For all objects in memory,
* Free unmarked objects,
* Unmark marked objects.
END

Slide.slide! "Roots", <<'END'
* Global Namespace : Kernel, Object
* Global Variables and CONSTANTS : $:, ARGV
* Local Variables : binding, caller
* self, &block
* Internals: rb_global_variable(), VALUEs on C stack.
END

mem.eval! 'Remove reference to "three"', <<'END', :before => true
x[3] = nil
END

Collector.new(mem).collect!

mem.eval! 'Remove References to Hash', <<'END', :before => true
y = nil
END

mem.eval! 'Remove References to Hash', <<'END'
x[-1] = nil
END

Collector.new(mem).collect!

Slide.slide! "3.times { x.pop } ", <<'END'
@@@ ruby

x.pop; x.pop; x.pop

@@@
END

3.times do
  mem.eval! 'x.pop', <<'END', :slide => false
x.pop
END
end

Collector.new(mem).collect!

Slide.slide! "Mark And Sweep Is Expensive", <<'END'
* Every reachable object is read.
* Every mark bit is read and mutated.
* Even if most of objects are not garbage (Modules, Methods, CONSTANTS, literals).
* Every freed object is mutated due to free list.
END

Slide.slide! "Coding Styles affect GC", <<'END'
* Every evaluated String, Float, String literal creates a new object.
* Shared String buffers reduce memory usage, but do not improve GC times.
* Every Float, Bignum math operation creates a new Object.
* Use String#<<, not String#+.
* big_enumerable.clear
* heavy_object = nil
END

mem.eval! "Set with Literal", <<'END', :before => true
x[3] = "three, again!"
END

Slide.slide! "Mark bits", <<'END'
h2. Copy-On-Write pages after process fork().

* CRuby <2.0
** Mark bits are at the head of each object.
** Faster, but page mutations happen *everywhere*.
* REE, CRuby 2.0 (HEAD)
** Mark bits are stored in external arrays.
** Slower.
END

mem.mark_bits!
Collector.new(mem).mark_roots!("With Mark Bits")

Slide.slide! "JRuby, Rubinius", <<'END'
* Rubinius has multiple collectors.
* JVM Collectors are highly-tuned.
* Some Commercial JVMS have *very* performant collectors.
END

Slide.slide! "Other GC Features", <<'END'
* Parallel Sweep - not seen yet.
* Parallel Mark - prototype presented at RubyConf 2011.
* Lazy Sweep - already in CRuby
* N-color marking
** Tredmill - "":https://github.com/kstephens/tredmill
** Needs Write Barrier
* Generational - difficult, unlikely.
** Needs Write Barrier
* Weak References
END

Slide.slide! "CRuby GC Options", <<'END'
h2. mem_api - "":http://github.com/kstephens/ruby
* Runtime hooks for different GCs/memory systems.
* Malloc-only
* Core
* BDW (in-progress)
* SMAL - "":http://github.com/kstephens/smal (in-progress)
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

Slide.slide! "Weak Reference", <<'END'
* Weak Reference only maintains its reference, iff one or more non-weak refereence also exist.
* Useful for caching.
* Soft References release references when under "memory pressure"
* Reference Queues contain dead Weak References.
END

Slide.slide! "Weak Reference Support", <<'END'
* JRuby
** Weak References, Soft References, Reference Queues.
* Rubinius
** Weak References
* CRuby
** ref - "":http://github.com/kstephens/ref : Weak, Soft, RefQueues
** Needs mem_api.
END


Slide.slide! "Questions", <<'END'
END

