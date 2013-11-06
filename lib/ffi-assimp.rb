require 'ffi'

module Assimp
  extend FFI::Library
  ffi_lib "assimp"
  #http://assimp.sourceforge.net/lib_html/cimport_8h.html#a09fe8ba0c8e91bf04b4c29556be53b6d

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
  DEFAULT_FLAGS = FLAG_aiProcess_CalcTangentSpace | FLAG_aiProcess_GenNormals | FLAG_aiProcess_JoinIdenticalVertices | FLAG_aiProcess_Triangulate | \
                  FLAG_aiProcess_GenUVCoords | FLAG_aiProcess_SortByPType | FLAG_aiProcess_LimitBoneWeights | 0

  def self.opengl_mat4(t)
    [
      t[0], t[4], t[8], t[12],
      t[1], t[5], t[9], t[13],
      t[2], t[6], t[10], t[14],
      t[3], t[7], t[11], t[15],
    ]
  end

  def self.open_file(filename, flags=DEFAULT_FLAGS, &blk)
    ai_ptr = Assimp.aiImportFile(filename, Assimp::DEFAULT_FLAGS)
    scene = Assimp::Scene.new(ai_ptr)
    root_node = Assimp::Node.new(scene[:node])
    blk.call(scene, root_node) if blk
    Assimp.aiReleaseImport(scene)
  end

  class Face < FFI::Struct
    layout(
      :num_indices, :uint32, # Index of the vertex which is influenced by the bone.
      :indices, :pointer,
    )
    def indices
      self[:indices].get_array_of_uint32(0, self[:num_indices])
    end
  end

  class VertexWeight < FFI::Struct
    layout(
      :vertex_id, :uint32, # Index of the vertex which is influenced by the bone.
      :weight, :float,
    )
  end

  class Bone < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_weights, :uint32,
      :weights, :pointer,

      :matrix, [:float, 16], # Matrix that transforms from mesh space to bone space in bind pose
    )
    def weights
      if self[:num_weights] > 0
        offset = -VertexWeight.size
        self[:num_weights].times.map{ offset += VertexWeight.size
          VertexWeight.new(self[:weights] + offset).values
        }
      else
        []
      end
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

      :colors, [:pointer, AI_MAX_NUMBER_OF_COLOR_SETS],    # C_STRUCT aiColor4D* mColors[AI_MAX_NUMBER_OF_COLOR_SETS];
      :texture_coords,[:pointer, AI_MAX_NUMBER_OF_TEXTURECOORDS] ,# C_STRUCT aiVector3D* mTextureCoords[AI_MAX_NUMBER_OF_TEXTURECOORDS];

      :num_uv_components, [:uint32, AI_MAX_NUMBER_OF_TEXTURECOORDS], # unsigned int mNumUVComponents[AI_MAX_NUMBER_OF_TEXTURECOORDS];

      :faces, :pointer,

      :num_bones, :uint32,
      :bones, :pointer,

      :material_index, :uint32,

      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_anim_meshes, :uint32,
      :anim_meshes, :pointer
    )


    def vertices
      self[:num_vertices] > 0 ? self[:vertices].get_array_of_float(0, self[:num_vertices]*3).each_slice(3).to_a : []
    end

    def normals
      return [] if self[:normals].null?
      self[:num_vertices] > 0 ? self[:normals].get_array_of_float(0, (self[:num_vertices]*3)*3).each_slice(3).to_a : []
    end

    def colors
      colors = []
      self[:colors].each{|i| colors << i.get_array_of_float(0, (self[:num_vertices]*3)*4).each_slice(4).to_a unless i.null? }
      colors
    end

    def texture_coords
      coords = []
      self[:texture_coords].each{|i| coords << i.get_array_of_float(0, (self[:num_vertices]*3)*3).each_slice(3).to_a unless i.null? }
      coords
    end

    def tangents
      return [] if self[:tangents].null?
      self[:num_vertices] > 0 ? self[:tangents].get_array_of_float(0, self[:num_vertices]) : []
    end

    def bitangents
      return [] if self[:bitangents].null?
      self[:num_vertices] > 0 ? self[:bitangents].get_array_of_float(0, self[:num_vertices]) : []
    end

    def faces
      if self[:num_faces] > 0
        offset = -Face.size
        self[:num_faces].times.map{ offset += Face.size
          Face.new(self[:faces] + offset).indices
        }
      else
        []
      end
    end

    def bones
      if self[:num_bones] > 0
        self[:bones].get_array_of_pointer(0, self[:num_bones]).map{|i| Bone.new(i) }
      else
        []
      end
    end

    def anim_meshes
      self[:num_anim_meshes] > 0 ? self[:anim_meshes].get_array_of_pointer(0, self[:num_anim_meshes]) : [] # TODO add AnimMeshes.new(i)
    end

    def num_uv_components; self[:num_uv_components].to_a; end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end
  end

  class VectorKey < FFI::Struct
    layout(:time, :double, :value, [:float, 3])
    def value; self[:value].to_a; end
  end

  class QuatKey < FFI::Struct
    layout(:time, :double, :value, [:float, 4])
    def value; self[:value].to_a; end
  end

  class NodeAnim < FFI::Struct
    layout(
      :name_length, :size_t,
      :name_data, [:uint8, MAXLEN],

      :num_position_keys, :uint32,
      :position_keys, :pointer,
      # C_STRUCT aiVectorKey* mPositionKeys;

      :num_rotation_keys, :uint32,
      :rotation_keys, :pointer,
      # C_STRUCT aiQuatKey* mRotationKeys;

      :num_scaling_keys, :uint32,
      :scaling_keys, :pointer,
      # C_STRUCT aiVectorKey* mScalingKeys;

      :pre_state, :uint8,
      :post_state, :uint8,
      # C_ENUM aiAnimBehaviour mPreState;
      # C_ENUM aiAnimBehaviour mPostState;
    )

    def position_keys
      if self[:num_position_keys] > 0
        offset = -VectorKey.size
        self[:num_position_keys].times.map{ offset += VectorKey.size
          v = VectorKey.new(self[:position_keys] + offset)
          [v[:time], v.value]
        }
      else
        []
      end
    end

    def scaling_keys
      if self[:num_scaling_keys] > 0
        offset = -VectorKey.size
        self[:num_scaling_keys].times.map{ offset += VectorKey.size
          v = VectorKey.new(self[:scaling_keys] + offset)
          [v[:time], v.value]
        }
      else
        []
      end
    end

    def rotation_keys
      if self[:num_scaling_keys] > 0
        offset = -QuatKey.size
        self[:num_rotation_keys].times.map{ offset += QuatKey.size
          v = QuatKey.new(self[:rotation_keys] + offset)
          [v[:time], v.value]
        }
      else
        []
      end
    end

    def pre_state; self[:pre_state]; end
    def post_state; self[:post_state]; end

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
      if self[:num_channels] > 0
        self[:channels].get_array_of_pointer(0, self[:num_channels]).map{|i| NodeAnim.new(i) }
      else
        []
      end
    end

    def mesh_channels
      if self[:num_mesh_channels] > 0
        self[:mesh_channels].get_array_of_pointer(0, self[:num_mesh_channels]).map{|i| MeshAnim.new(i) }
      else
        []
      end
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
      self[:parent].null? ? nil : Node.new(self[:parent])
    end

    def children
      if self[:num_children] > 0
        self[:children].get_array_of_pointer(0, self[:num_children]).map{|i| Node.new(i) }
      else
        []
      end
    end

    def meshes_index
      if self[:num_meshes] > 0
        self[:meshes].get_array_of_uint32(0, self[:num_meshes])
      else
        []
      end
    end

    def name
      self[:name_data].to_a.pack("C#{self[:name_length]}")
    end

    def transformation_matrix
      Assimp.opengl_mat4(self[:transformation].to_a)
    end

    def test_find_node(n)
      return self if n == name
      found = nil
      children.each{|i| found = i.test_find_node(n); break if found }
      found
    end

    def node_inspect
      {
        name: name,
        #transformation_matrix: transformation_matrix,
        parent: parent && parent.name,
        children: children.map{|e| e.node_inspect },
        #meshes_index: meshes_index,
      }
    end
    def node_hash
      {
        name: name,
        transformation_matrix: transformation_matrix,
        children: children.map{|e| e.node_hash },
      }
    end
  end

  class Scene < FFI::Struct
    layout(
      :flags, :uint32,
      :node, :pointer,
      #:node, Node,

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

      :private, :pointer, # Internal data, do not touch
    )

    def meshes
      if self[:num_meshes] > 0
        self[:meshes].get_array_of_pointer(0, self[:num_meshes]).map{|i| Mesh.new(i) }
      else
        []
      end
    end

    def info
      @info ||= Hash[ *[:num_meshes, :num_materials, :num_animations, :num_textures, :num_lights, :num_cameras].map{|i| [i, self[i]] }.flatten ]
    end

    def animations
      if self[:num_animations] > 0
        self[:animations].get_array_of_pointer(0, self[:num_animations]).map{|i| Animation.new(i) }
      else
        []
      end
    end
  end

  # ASSIMP_API const aiScene* aiImportFile  ( const char *  pFile, unsigned int  pFlags ) 
  #attach_function :aiImportFile, [:string, :int], :pointer
  attach_function :aiImportFile, [:string, :int], Scene

  # ASSIMP_API const aiScene* aiImportFileFromMemory  ( const char *  pBuffer, unsigned int  pLength, unsigned int  pFlags, const char *  pHint ) 
  #attach_function :aiImportFileFromMemory, [:pointer, :int, :int, :string], :pointer
  attach_function :aiImportFileFromMemory, [:pointer, :int, :int, :string], Scene

  # ASSIMP_API void aiReleaseImport ( const aiScene *   pScene  ) 
  #attach_function :aiReleaseImport, [:pointer], :void
  attach_function :aiReleaseImport, [Scene], :void

end
