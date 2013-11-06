#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>
#include <glm/gtx/transform.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "anim.h"


void bone_transform( double current_time, animation* a, node* n, glm::mat4* transforms)
{
  float ticks_per_second = (float)(a->ticks_per_second != 0 ? a->ticks_per_second : 25.0f);
  float time_in_ticks = current_time * ticks_per_second;
  float animation_time = fmod(time_in_ticks, (float)a->duration);

  //glm::mat4 scene_transformation = glm::mat4(1.0f);
  glm::mat4 scene_transformation = glm::inverse( *(n->transformation_matrix) );

  read_node_heirachy(animation_time, a, n, scene_transformation, transforms);
}

const channel* find_animation_channel(animation* a, int32_t bone_id)
{
  for (uint8_t i=0 ; i < a->num_channels ; i++) {
    channel* node_anim = a->channels[i];
    if (bone_id == node_anim->bone_id) { return node_anim; }
  }; return NULL;
}

uint32_t find_rotation(float animation_time, const channel* node_anim)
{
  for (uint32_t i=0 ; i < node_anim->num_rotations - 1 ; i++) {
    if (animation_time < node_anim->rotations[i+1]->time) { return i; }
  }; return 0;
}

uint32_t find_position(float animation_time, const channel* node_anim)
{
  for (uint32_t i=0 ; i < node_anim->num_positions - 1 ; i++) {
    if (animation_time < node_anim->positions[i+1]->time) { return i; }
  }; return 0;
}

glm::vec3 calc_interpolated_position(float animation_time, const channel* node_anim)
{
  if (node_anim->num_positions == 1) { return node_anim->positions[0]->vector; }   

  uint32_t index = find_position(animation_time, node_anim);
  uint32_t next_index = (index+1);

  float delta_time = (float)(node_anim->rotations[next_index]->time - node_anim->rotations[index]->time);
  float factor = (animation_time - (float)node_anim->rotations[index]->time) / delta_time;

  glm::vec3 start = node_anim->positions[index]->vector;
  glm::vec3 end   = node_anim->positions[next_index]->vector;

  glm::vec3 delta = end - start;
  glm::vec3 out   = start + factor * delta;
  return out;
}

glm::quat calc_interpolated_rotataion(float animation_time, const channel* node_anim)
{
  if (node_anim->num_rotations == 1) { return node_anim->rotations[0]->quat; }   

  uint32_t index = find_rotation(animation_time, node_anim);
  uint32_t next_index = (index+1);

  float delta_time = (float)(node_anim->rotations[next_index]->time - node_anim->rotations[index]->time);
  float factor = (animation_time - (float)node_anim->rotations[index]->time) / delta_time;
  
  glm::quat start = node_anim->rotations[index]->quat;
  glm::quat end   = node_anim->rotations[next_index]->quat;

  //glm::quat out = glm::slerp(start, end, factor);
  glm::quat out = glm::mix(start, end, factor);
  return glm::normalize(out);
}

void read_node_heirachy(float animation_time, animation* a, node* n, glm::mat4 parent_transform, glm::mat4* transforms)
{
  glm::mat4 node_transformation = *(n->transformation_matrix);

  if (n->bone_index != -1){
    const channel* node_anim = find_animation_channel(a, n->bone_index);

    if (node_anim){
      glm::quat rot = calc_interpolated_rotataion(animation_time, node_anim);
      glm::mat4 rot_mat = glm::toMat4(rot);

      glm::vec3 pos = calc_interpolated_position(animation_time, node_anim);
      glm::mat4 pos_mat = glm::translate(glm::mat4(1.0f), pos);

      node_transformation = pos_mat * rot_mat;
    }
  }

  glm::mat4 global_transformation = parent_transform * node_transformation;

  if (n->bone_index != -1){
    transforms[n->bone_index] = global_transformation * *(n->offset_matrix);
  }

  for (uint8_t i=0 ; i < n->num_children; i++) {
    read_node_heirachy(animation_time, a, n->children[i], global_transformation, transforms);
  }
}


void matrix_inverse(glm::mat4* in, glm::mat4* out)
{
  glm::mat4 o = glm::inverse( *(in) );
  //glm::mat4 o = glm::inverse( glm::mat4(1.0) );
  //memcpy(out, glm::value_ptr(o), sizeof(o));
  //glm::mat4 o = glm::mat4(1.0);
  *out = o;
}

#include <glm/gtc/matrix_inverse.hpp>
 
void matrix_to_normal_matrix(glm::mat4* in, glm::mat4* out)
{
  *out = glm::mat4( glm::inverseTranspose(glm::mat3( *(in) )) );
}

