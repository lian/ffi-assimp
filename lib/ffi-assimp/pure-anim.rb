module PureAnim

  class AnimStruct
    attr_reader :animations, :root_node, :bone_info, :bone_index, :bones_count, :bone_transformations, :bone_weights
    def initialize(scene, root_node)
      @mat_utils = MathUtils.new

      load_meshes_meta(scene)
      scene.meshes.each.with_index{|mesh,idx| load_bones(idx, mesh) }

      @animations = scene.animations.map{|a| copy_assimp_animation_to_libanim(a) }
      @root_node  = copy_assimp_node_heirarchy_to_libanim(root_node)

      @bones_count = @bone_info.size
      @bone_transformations = FFI::MemoryPointer.new(:float, @bones_count*16)
    end

    def copy_assimp_animation_to_libanim(a)
      {
        name: a.name, ticks_per_second: a[:ticks_per_second], duration: a[:duration],
        channels: Hash[*a.channels.map{|n| [n.name, { name: n.name, position_keys: n.position_keys, rotation_keys: n.rotation_keys, scaling_keys: n.scaling_keys, pre_state: n.pre_state, post_state: n.post_state }] }.flatten]
      }
    end

    def copy_assimp_node_heirarchy_to_libanim(root_node)
      @global_inverse_transfrom = Assimp.opengl_mat4(root_node.transformation_matrix) # wrong but working for now
      @global_root_transform = @mat_utils.mat4_multiply(@global_inverse_transfrom, MathUtils::IdentityMatrix)
      @root_node = root_node.node_hash
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

    def bone_transform(animation_index, time)
      if animation = @animations[animation_index]
        time_in_seconds = time % animation[:duration]
        ticks_per_second = animation[:ticks_per_second] != 0 ? animation[:ticks_per_second] : 25.0
        time_in_ticks = time_in_seconds * ticks_per_second
        animation_time = time_in_ticks.divmod(animation[:duration]).last

        root_transform = @global_root_transform
        read_node_heirachy(animation_time, animation, @root_node, @global_root_transform)

        transforms = @bone_info.map{|v| v[:final_transformation] }
        @bone_transformations.put_array_of_float(0, transforms.flatten)
      end
    end

    def read_node_heirachy(animation_time, animation, node, parent_transform)
      node_name = node[:name]

      if node_anim = animation[:channels][node_name]
        rotation    = calc_interpolated_rotation(animation_time, node_anim)
        translation = calc_interpolated_position(animation_time, node_anim)
        node_transformation = @mat_utils.mat4_multiply(translation, rotation)
        #NodeTransformation = TranslationM * RotationM * ScalingM;
      else
        node_transformation = node[:transformation_matrix]
      end
      global_transformation = @mat_utils.mat4_multiply(parent_transform, node_transformation)

      if bone_index = @bone_index[node_name]
        @bone_info[bone_index][:final_transformation] = @mat_utils.mat4_multiply(global_transformation, @bone_info[bone_index][:bone_offset])
      end

      node[:children].each{|child|
        read_node_heirachy(animation_time, animation, child, global_transformation)
      }
    end

    def calc_interpolated_position(animation_time, node_anim)
      if node_anim[:position_keys].size == 1
        time, value = node_anim[:position_keys][0]; value
      end

      index = find_position(animation_time, node_anim)
      next_index = index + 1
      next_index = 0 unless node_anim[:position_keys][next_index]
      delta_time = node_anim[:position_keys][next_index][0] - node_anim[:position_keys][index][0]
      factor = (animation_time - node_anim[:position_keys][index][0]) / delta_time
      start = node_anim[:position_keys][index][1]
      stop = node_anim[:position_keys][next_index][1]
      delta = [ stop[0]-start[0], stop[1]-start[1], stop[2]-start[2] ]
      #out = start + factor * delta
      [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        start[0] + (factor * delta[0]), start[1] + (factor * delta[1]), start[2] + (factor * delta[2]),  1.0,
      ]
    end

    def calc_interpolated_rotation(animation_time, node_anim)
      if node_anim[:rotation_keys].size == 1
        time, value = node_anim[:rotation_keys][0]
        p :only_one_rotation_key
        value
      end

      index = find_rotation(animation_time, node_anim)
      next_index = index + 1
      next_index = 0 unless node_anim[:rotation_keys][next_index]
      delta_time = node_anim[:rotation_keys][next_index][0] - node_anim[:rotation_keys][index][0]
      factor = (animation_time - node_anim[:rotation_keys][index][0]) / delta_time
      start = node_anim[:rotation_keys][index][1]
      stop = node_anim[:rotation_keys][next_index][1]
      delta = [ stop[0]-start[0], stop[1]-start[1], stop[2]-start[2] ]

      q = Anim::Quat.interpolate( Anim::Quat.new(*start), Anim::Quat.new(*stop), factor)
      q.normalize.to_mat
    end

    def find_position(animation_time, node_anim)
      node_anim[:position_keys].each.with_index{|(time,value),idx|
        if next_pos = node_anim[:position_keys][idx+1]
          return idx if animation_time < next_pos[0]
        end
      }; 0
    end

    def find_rotation(animation_time, node_anim)
      node_anim[:rotation_keys].each.with_index{|(time,value),idx|
        if next_pos = node_anim[:rotation_keys][idx+1]
          return idx if animation_time < next_pos[0]
        end
      }; 0
    end

  end


  class MathUtils
    IdentityMatrix = [ 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0 ] #.freeze
    def mat4_multiply(m2, m1) # glm seems to twist them
      [ (m1[0]*m2[0])  + (m1[1]*m2[4])  + (m1[2]*m2[8])   + (m1[3]*m2[12])   ,
        (m1[0]*m2[1])  + (m1[1]*m2[5])  + (m1[2]*m2[9])   + (m1[3]*m2[13])   ,
        (m1[0]*m2[2])  + (m1[1]*m2[6])  + (m1[2]*m2[10])  + (m1[3]*m2[14])   ,
        (m1[0]*m2[3])  + (m1[1]*m2[7])  + (m1[2]*m2[11])  + (m1[3]*m2[15])   ,

        (m1[4]*m2[0])  + (m1[5]*m2[4])  + (m1[6]*m2[8])   + (m1[7]*m2[12])   ,
        (m1[4]*m2[1])  + (m1[5]*m2[5])  + (m1[6]*m2[9])   + (m1[7]*m2[13])   ,
        (m1[4]*m2[2])  + (m1[5]*m2[6])  + (m1[6]*m2[10])  + (m1[7]*m2[14])   ,
        (m1[4]*m2[3])  + (m1[5]*m2[7])  + (m1[6]*m2[11])  + (m1[7]*m2[15])   ,

        (m1[8]*m2[0])  + (m1[9]*m2[4])  + (m1[10]*m2[8])  + (m1[11]*m2[12])  ,
        (m1[8]*m2[1])  + (m1[9]*m2[5])  + (m1[10]*m2[9])  + (m1[11]*m2[13])  ,
        (m1[8]*m2[2])  + (m1[9]*m2[6])  + (m1[10]*m2[10]) + (m1[11]*m2[14])  ,
        (m1[8]*m2[3])  + (m1[9]*m2[7])  + (m1[10]*m2[11]) + (m1[11]*m2[15])  ,

        (m1[12]*m2[0]) + (m1[13]*m2[4]) + (m1[14]*m2[8])  + (m1[15]*m2[12])  ,
        (m1[12]*m2[1]) + (m1[13]*m2[5]) + (m1[14]*m2[9])  + (m1[15]*m2[13])  ,
        (m1[12]*m2[2]) + (m1[13]*m2[6]) + (m1[14]*m2[10]) + (m1[15]*m2[14])  ,
        (m1[12]*m2[3]) + (m1[13]*m2[7]) + (m1[14]*m2[11]) + (m1[15]*m2[15])    ]
    end
  end


  class Quat
    attr_accessor :x, :y, :z, :w
    def initialize(w=1,x=0,y=0,z=0); @x,@y,@z,@w = x,y,z,w; end
    def length; Math.sqrt(dot); end
    def dot(q=self); @x * q.x + @y * q.y + @z * q.z + @w * q.w; end
    def normalize; l = length; l > 0 ? Quat.new( @w / l, @x / l, @y / l, @z / l ) : Quat.new; end

    # ported from: glm-0.9.0.7/glm/gtc/quaternion.inl line 437
    def to_mat(pos=[0,0,0])
      xx, xy, xz, xw = @x*@x, @x*@y, @x*@z, @x*@w
      yy, yz, yw = @y*@y, @y*@z, @y*@w
      zz, zw = @z*@z, @z*@w
      [
        1-2*(yy+zz), 2*(xy+zw), 2*(xz-yw), 0,
        2*(xy-zw), 1-2*(xx+zz), 2*(yz+xw), 0,
        2*(xz+yw), 2*(yz-xw), 1-2*(xx+yy), 0,
        pos[0], pos[1], pos[2], 1
      ]
    end

    def self.interpolate(start, stop, factor)
      cosom = start.x * stop.x  +  start.y * stop.y  +  start.z * start.z  +  start.w * stop.w

      if cosom < 0.0
        cosom = -cosom
        stop = stop.conjugate
      end

      # Calculate coefficients
      if (1.0 - cosom) > 0.0001 # some epsillon
        # Standard case (slerp)
        omega = Math.acos(cosom) #  extract theta from dot product's cos theta
        sinom = Math.sin(omega)
        sclp = Math.sin( (1.0-factor) * omega ) / sinom
        sclq = Math.sin( factor * omega ) / sinom
      else
        # Very close, do linear interp (because it's faster)
        sclp = 1.0-factor
        sclq = factor
      end

      Quat.new(
        sclp * start.w  +  sclq * stop.w,
        sclp * start.x  +  sclq * stop.x,
        sclp * start.y  +  sclq * stop.y,
        sclp * start.z  +  sclq * stop.z,
      )
    end
  end

end
