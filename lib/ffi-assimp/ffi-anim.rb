require 'ffi'

module Anim
  extend FFI::Library
  file = File.join(File.dirname(__FILE__), '../../ext/libassimp_anim_helper.so')
  unless File.exists?(file)
    Dir.chdir(File.dirname(file)){ system("make") } # compile once
    raise "compile: #{file} failed" unless File.exists?(file)
  end
  ffi_lib(file)

  class PositionKey < FFI::Struct
    layout(
      :time, :double,
      :x, :float,
      :y, :float,
      :z, :float,
    )
  end

  class RotationKey < FFI::Struct
    layout(
      :time, :double,
      #:w, :float,
      :x, :float,
      :y, :float,
      :z, :float,
      :w, :float, # move above x for casting from own structs to glm structs
    )
  end

  class Channel < FFI::Struct
    layout(
      :name, :pointer,
      :bone_id, :int32,
      :num_positions, :uint32,
      :positions, :pointer,
      :num_rotations, :uint32,
      :rotations, :pointer,
    )
  end

  class Node < FFI::Struct
    layout(
      :name, :pointer,
      :transformation_matrix, :pointer,
      :offset_matrix, :pointer,
      :bone_index, :int32,
      :num_children, :uint32,
      :children, :pointer,
    )
  end
  

  class Animation < FFI::Struct
    layout(
      :name, :pointer,
      :ticks_per_second, :double,
      :duration, :double,
      :num_channels, :uint32,
      :channels, :pointer
    )
  end

  class AnimStruct
    attr_reader :animations, :root_node, :bone_info, :bone_index, :bones_count, :bone_transformations, :bone_weights
    def initialize(scene, root_node)
      load_meshes_meta(scene)
      scene.meshes.each.with_index{|mesh,idx| load_bones(idx, mesh) }

      @animations = scene.animations.map{|a| copy_assimp_animation_to_libanim(a) }
      @root_node  = copy_assimp_node_heirarchy_to_libanim(root_node)

      @bones_count = @bone_info.size
      @bone_transformations = FFI::MemoryPointer.new(:float, @bones_count*16)
    end

    def bone_transform(animation_index, time)
      if animation = @animations[animation_index]
        time = time % animation[:duration]
        Anim.bone_transform(time, animation, @root_node, @bone_transformations)
      end
    end

    def load_meshes_meta(scene) # Count the number of vertices and indices
      num_vertices, num_indices = 0, 0
      @meshes_meta = scene.meshes.map{|mesh|
        t = { material_index: mesh[:material_index], num_indices: mesh.faces.flatten.size, base_vertex: num_vertices, base_index: num_indices }
        num_vertices += mesh[:num_vertices]
        num_indices += t[:num_indices]
        t
      }
    end

    def load_bones(idx, mesh)
      @bone_info ||= []
      @bone_index ||= {}
      num_bones = @bone_info.size
      @bone_weights ||= {}

      mesh.bones.each{|bone|
        bone_name = bone.name

        if @bone_index[bone.name]
          bone_index = @bone_index[bone.name]
        else
          bone_index = num_bones; num_bones += 1
          @bone_info << { bone_offset: bone.transformation_matrix }
          @bone_index[bone.name] = bone_index
        end

        bone.weights.each{|vertex_id,weight|
          vertex_id = @meshes_meta[idx][:base_vertex] + vertex_id
          @bone_weights[vertex_id] ||= []
          @bone_weights[vertex_id] << { bone_index: bone_index, weight: weight }
        }
      }
    end

    def refs
      @ffi_struct_refs_cache ||= []
    end

    def copy_assimp_node_heirarchy_to_libanim(node)
      n = Anim::Node.new
      refs << n
      n[:name] = FFI::MemoryPointer.from_string(node.name)
      n[:transformation_matrix] = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, node.transformation_matrix)
      #n[:offset_matrix] = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, node[:transformation_matrix])

      if bone_index = @bone_index[node.name]
        n[:offset_matrix] = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, @bone_info[bone_index][:bone_offset])
        n[:bone_index] = bone_index
      else
        #p "!!no bone offset matrix found for node: #{node.name}"
        n[:offset_matrix] = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, MatrixStack::IdentityMatrix)
        n[:bone_index] = -1
      end

      children = node.children.map{|child_node| copy_assimp_node_heirarchy_to_libanim(child_node) }
      n[:num_children] = children.size
      if children.size > 0
        childred_ptr = FFI::MemoryPointer.new(:pointer, n[:num_children]).put_array_of_pointer(0, children)
        n[:children] = childred_ptr
      end
      n
    end

    def copy_assimp_animation_to_libanim(animation)
      a = Anim::Animation.new
      refs << a
      a[:name] = FFI::MemoryPointer.from_string(animation.name)
      a[:ticks_per_second] = animation[:ticks_per_second]
      a[:duration] = animation[:duration]

      channels = animation.channels.map{|channel|
        c = Anim::Channel.new
        refs << c
        c[:name] = FFI::MemoryPointer.from_string(channel.name)

        if bone_index = @bone_index[channel.name]
          c[:bone_id] = bone_index
        else
          c[:bone_id] = -1
        end

        positions = channel.position_keys.map{|time, vertex|
          v = Anim::PositionKey.new
          refs << v
          v[:time] = time
          v[:x] = vertex[0]
          v[:y] = vertex[1]
          v[:z] = vertex[2]
          v
        }
        c[:num_positions] = positions.size
        positions_ptr = FFI::MemoryPointer.new(:pointer, c[:num_positions]).put_array_of_pointer(0, positions)
        c[:positions] = positions_ptr

        rotations = channel.rotation_keys.map{|time, vertex|
          v = Anim::RotationKey.new
          refs << v
          v[:time] = time
          v[:w] = vertex[0]
          v[:x] = vertex[1]
          v[:y] = vertex[2]
          v[:z] = vertex[3]
          v
        }
        c[:num_rotations] = rotations.size
        rotations_ptr = FFI::MemoryPointer.new(:pointer, c[:num_rotations]).put_array_of_pointer(0, rotations)
        c[:rotations] = rotations_ptr
        c
      }

      a[:num_channels] = channels.size
      channels_ptr = FFI::MemoryPointer.new(:pointer, a[:num_channels]).put_array_of_pointer(0, channels)
      a[:channels] = channels_ptr

      a
    end

  end

  #attach_function :bone_transform, [:double, :pointer, :pointer, :pointer, :pointer], :void
  attach_function :bone_transform, [:double, :pointer, :pointer, :pointer], :void
  attach_function :matrix_inverse, [:pointer, :pointer], :void
  attach_function :matrix_to_normal_matrix, [:pointer, :pointer], :void
end


if $0 == __FILE__

# test matrix_inverse
a = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0])
b = FFI::MemoryPointer.new(:float, 16)
p a.get_array_of_float(0, 16)
p b.get_array_of_float(0, 16)
Anim.matrix_inverse(a, b)
p a.get_array_of_float(0, 16)
p b.get_array_of_float(0, 16)

# test matrix_to_normal_matrix
a = FFI::MemoryPointer.new(:float, 16).put_array_of_float(0, [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0])
b = FFI::MemoryPointer.new(:float, 16)
p a.get_array_of_float(0, 16)
p b.get_array_of_float(0, 16)
Anim.matrix_to_normal_matrix(a, b)
p a.get_array_of_float(0, 16)
p b.get_array_of_float(0, 16)


# test struts and bone_transform
a = Anim::Animation.new

a[:name] = FFI::MemoryPointer.from_string("hello")
a[:ticks_per_second] = 1.1
a[:duration] = 1.2
a[:num_channels] = 100

c1 = Anim::Channel.new
c1[:name] = FFI::MemoryPointer.from_string("chan1")
c1[:num_positions] = 1
pos1 = Anim::PositionKey.new
pos1[:time] = 0.5
pos1[:x] = 1.1
pos1[:y] = 2.2
pos1[:z] = 3.3
positions = FFI::MemoryPointer.new(:pointer, 1).put_array_of_pointer(0, [pos1])
c1[:positions] = positions

c1[:num_rotations] = 1
pos1 = Anim::RotationKey.new
pos1[:time] = 0.5
pos1[:w] = 4.4
pos1[:x] = 1.1
pos1[:y] = 2.2
pos1[:z] = 3.3
rotations = FFI::MemoryPointer.new(:pointer, 1).put_array_of_pointer(0, [pos1])
c1[:rotations] = rotations


c2 = Anim::Channel.new
c2[:name] = FFI::MemoryPointer.from_string("chan2")
c2[:num_positions] = 3

channels = FFI::MemoryPointer.new(:pointer, 2).put_array_of_pointer(0, [c1, c2])

a[:num_channels] = 2
a[:channels] = channels


Anim.bone_transform(a)

end
