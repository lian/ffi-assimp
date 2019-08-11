require "ffi"

module Assimp
  extend FFI::Library

  # http://assimp.sourceforge.net/lib_html/cimport_8h.html#a09fe8ba0c8e91bf04b4c29556be53b6d
  ffi_lib "assimp"

  MAXLEN = 1024

  AI_MAX_NUMBER_OF_TEXTURECOORDS = 0x8
  AI_MAX_NUMBER_OF_COLOR_SETS = 0x8

  FLAG_aiProcess_CalcTangentSpace = 0x1
  FLAG_aiProcess_JoinIdenticalVertices = 0x2
  FLAG_aiProcess_Triangulate = 0x8
  FLAG_aiProcess_GenNormals = 0x20
  FLAG_aiProcess_GenUVCoords = 0x40000
  FLAG_aiProcess_SortByPType = 0x8000
  FLAG_aiProcess_LimitBoneWeights = 0x200

  DEFAULT_FLAGS = FLAG_aiProcess_CalcTangentSpace |
                  FLAG_aiProcess_GenNormals |
                  FLAG_aiProcess_JoinIdenticalVertices |
                  FLAG_aiProcess_Triangulate |
                  FLAG_aiProcess_GenUVCoords |
                  FLAG_aiProcess_SortByPType |
                  FLAG_aiProcess_LimitBoneWeights |
                  0

  module_function

  def opengl_mat4(t)
    [
      t[0], t[4], t[8], t[12],
      t[1], t[5], t[9], t[13],
      t[2], t[6], t[10], t[14],
      t[3], t[7], t[11], t[15],
    ]
  end

  def open_file(path, flags = DEFAULT_FLAGS)
    scene_pointer = Assimp.aiImportFile(path, flags)
    scene = Assimp::Scene.new(scene_pointer)
    root_node = Assimp::Node.new(scene[:node])
    yield scene, root_node
  ensure
    Assimp.aiReleaseImport(scene)
  end

  class Face < FFI::Struct
    layout(
      # Index of the vertex which is influenced by the bone.
      :num_indices, :uint32,

      :indices, :pointer,
    )

    def indices
      self[:indices].get_array_of_uint32(0, self[:num_indices])
    end
  end

  class VertexWeight < FFI::Struct
    layout(
      # Index of the vertex which is influenced by the bone.
      :vertex_id, :uint32,

      :weight, :float,
    )
  end

  class Bone < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_weights, :uint32,
      :weights, :pointer,

      # Matrix that transforms from mesh space to bone space in bind pose
      :matrix, [:float, 16],
    )

    def weights
      return [] unless self[:num_weights] > 0

      offset = -VertexWeight.size

      self[:num_weights].times.map {
        offset += VertexWeight.size
        VertexWeight.new(self[:weights] + offset).values
      }
    end

    def transformation_matrix
      Assimp.opengl_mat4(self[:matrix].to_a)
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end
  end

  class Mesh < FFI::Struct
    layout(
      :primitive_types, :uint32,
      :num_vertices, :uint32,
      :num_faces, :uint32,

      :vertices, :pointer,
      :normals, :pointer,
      :tangents, :pointer,
      :bitangents, :pointer,

      # C_STRUCT aiColor4D* mColors[AI_MAX_NUMBER_OF_COLOR_SETS];
      :colors, [:pointer, AI_MAX_NUMBER_OF_COLOR_SETS],

      # C_STRUCT aiVector3D* mTextureCoords[AI_MAX_NUMBER_OF_TEXTURECOORDS];
      :texture_coords, [:pointer, AI_MAX_NUMBER_OF_TEXTURECOORDS],

      # unsigned int mNumUVComponents[AI_MAX_NUMBER_OF_TEXTURECOORDS];
      :num_uv_components, [:uint32, AI_MAX_NUMBER_OF_TEXTURECOORDS],

      :faces, :pointer,

      :num_bones, :uint32,
      :bones, :pointer,

      :material_index, :uint32,

      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_anim_meshes, :uint32,
      :anim_meshes, :pointer,
    )


    def vertices
      return [] unless self[:num_vertices] > 0

      self[:vertices]
        .get_array_of_float(0, self[:num_vertices] * 3)
        .each_slice(3)
        .to_a
    end

    def normals
      return [] if self[:normals].null?
      return [] unless self[:num_vertices] > 0

      self[:normals]
        .get_array_of_float(0, (self[:num_vertices] * 3) * 3)
        .each_slice(3)
        .to_a
    end

    def colors
      self[:colors].reject(&:null?).map do |pointer|
        pointer
          .get_array_of_float(0, (self[:num_vertices] * 3) * 4)
          .each_slice(4)
          .to_a
      end
    end

    def texture_coords
      self[:texture_coords].reject(&:null?).each do |pointer|
        pointer
          .get_array_of_float(0, (self[:num_vertices] * 3) * 3)
          .each_slice(3)
          .to_a
      end
    end

    def tangents
      return [] if self[:tangents].null?
      return [] unless self[:num_vertices] > 0

      self[:tangents].get_array_of_float(0, self[:num_vertices])
    end

    def bitangents
      return [] if self[:bitangents].null?
      return [] unless self[:num_vertices] > 0

      self[:bitangents].get_array_of_float(0, self[:num_vertices])
    end

    def faces
      return [] unless self[:num_faces] > 0

      offset = -Face.size
      self[:num_faces].times.map {
        offset += Face.size
        Face.new(self[:faces] + offset).indices
      }
    end

    def bones
      return [] unless self[:num_bones] > 0

      self[:bones]
        .get_array_of_pointer(0, self[:num_bones])
        .map{ |pointer| Bone.new(pointer) }
    end

    def anim_meshes
      return [] unless self[:num_anim_meshes] > 0

      self[:anim_meshes].get_array_of_pointer(0, self[:num_anim_meshes])
    end

    def num_uv_components
      self[:num_uv_components].to_a
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end
  end

  class VectorKey < FFI::Struct
    layout(:time, :double, :value, [:float, 3])

    def value
      self[:value].to_a
    end
  end

  class QuatKey < FFI::Struct
    layout(:time, :double, :value, [:float, 4])

    def value
      self[:value].to_a
    end
  end

  class NodeAnim < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_position_keys, :uint32,

      # C_STRUCT aiVectorKey* mPositionKeys;
      :position_keys, :pointer,

      :num_rotation_keys, :uint32,

      # C_STRUCT aiQuatKey* mRotationKeys;
      :rotation_keys, :pointer,

      :num_scaling_keys, :uint32,

      # C_STRUCT aiVectorKey* mScalingKeys;
      :scaling_keys, :pointer,

      # C_ENUM aiAnimBehaviour mPreState;
      :pre_state, :uint8,

      # C_ENUM aiAnimBehaviour mPostState;
      :post_state, :uint8,
    )

    def position_keys
      return [] unless self[:num_position_keys] > 0

      offset = -VectorKey.size

      self[:num_position_keys].times.map {
        offset += VectorKey.size
        v = VectorKey.new(self[:position_keys] + offset)
        [v[:time], v.value]
      }
    end

    def scaling_keys
      return [] unless self[:num_scaling_keys] > 0

      offset = -VectorKey.size
      self[:num_scaling_keys].times.map {
        offset += VectorKey.size
        v = VectorKey.new(self[:scaling_keys] + offset)
        [v[:time], v.value]
      }
    end

    def rotation_keys
      return [] unless self[:num_scaling_keys] > 0

      offset = -QuatKey.size
      self[:num_rotation_keys].times.map {
        offset += QuatKey.size
        v = QuatKey.new(self[:rotation_keys] + offset)
        [v[:time], v.value]
      }
    end

    def pre_state
      self[:pre_state]
    end

    def post_state
      self[:post_state]
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end
  end

  class Animation < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],
      :duration, :double,
      :ticks_per_second, :double,
      :num_channels, :uint32,
      :channels, :pointer,
      :num_mesh_channels, :uint32,
      :mesh_channels, :pointer,
    )

    def channels
      return [] unless self[:num_channels] > 0

      self[:channels]
        .get_array_of_pointer(0, self[:num_channels])
        .map { |pointer| NodeAnim.new(pointer) }
    end

    def mesh_channels
      return [] unless self[:num_mesh_channels] > 0

      self[:mesh_channels]
        .get_array_of_pointer(0, self[:num_mesh_channels])
        .map { |pointer| MeshAnim.new(pointer) }
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end
  end

  class Node < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :transformation, [:float, 16],

      :parent, :pointer,

      :num_children, :uint32,
      :children, :pointer,
      :num_meshes, :uint32,
      :meshes, :pointer,
    )

    def parent
      Node.new(self[:parent]) unless self[:parent].null?
    end

    def children
      return [] unless self[:num_children] > 0

      self[:children]
        .get_array_of_pointer(0, self[:num_children])
        .map{ |pointer| Node.new(pointer) }
    end

    def meshes_index
      return [] unless self[:num_meshes] > 0

      self[:meshes].get_array_of_uint32(0, self[:num_meshes])
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end

    def transformation_matrix
      Assimp.opengl_mat4(self[:transformation].to_a)
    end

    def test_find_node(n)
      return self if n == name

      children.each do |node|
        found = node.test_find_node(n)
        return found if found
      end
    end

    def node_inspect
      {
        name: name,
        parent: parent&.name,
        children: children.map(&:node_inspect),
      }
    end

    def node_hash
      {
        name: name,
        transformation_matrix: transformation_matrix,
        children: children.map(&:node_hash),
      }
    end
  end

  class Scene < FFI::Struct
    layout(
      :flags, :uint32,

      # :node, Node,
      :node, :pointer,

      :num_meshes, :uint32,
      :meshes, :pointer,

      :num_materials, :uint32,
      :materials, :pointer,

      :num_animations, :uint32,
      :animations, :pointer,

      :num_textures, :uint32,
      :textures, :pointer,

      :num_lights, :uint32,
      :lights, :pointer,

      :num_cameras, :uint32,
      :cameras, :pointer,

      # Internal data, do not touch
      :private, :pointer,
    )

    def meshes
      return unless self[:num_meshes] > 0

      self[:meshes]
        .get_array_of_pointer(0, self[:num_meshes])
        .map { |pointer| Mesh.new(pointer) }
    end

    def info
      @info ||= begin
        keys = %i[
          num_meshes
          num_materials
          num_animations
          num_textures
          num_lights
          num_cameras
        ]
        Hash[*keys.flat_map { |key| [key, self[key]] }]
      end
    end

    def animations
      return [] unless self[:num_animations] > 0

      self[:animations]
        .get_array_of_pointer(0, self[:num_animations])
        .map { |pointer| Animation.new(pointer) }
    end
  end

  # const aiScene* aiImportFile (const char * pFile, unsigned int pFlags)
  attach_function :aiImportFile, %i[string int], Scene

  # const aiScene* aiImportFileFromMemory
  # (const char * pBuffer,
  #  unsigned int  pLength,
  #  unsigned int pFlags,
  #  const char * pHint)
  attach_function :aiImportFileFromMemory, %i[pointer int int string], Scene

  # void aiReleaseImport (const aiScene * pScene)
  attach_function :aiReleaseImport, [Scene], :void
end
