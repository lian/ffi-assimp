#ifndef ANIM_INCLUDED
#define ANIM_INCLUDED


struct position_key
{
  double time;
  glm::vec3 vector;
};

struct rotation_key
{
  double time;
  glm::quat quat;
};

struct channel
{
  char* name;
  int32_t bone_id;
  uint32_t num_positions;
  struct position_key** positions;
  uint32_t num_rotations;
  struct rotation_key** rotations;
};

struct animation
{
  char* name;
  double ticks_per_second;
  double duration;
  uint32_t num_channels;
  struct channel** channels;
};

struct node
{
  char* name;
  glm::mat4* transformation_matrix;
  glm::mat4* offset_matrix;
  int32_t bone_index;
  uint32_t num_children;
  node** children;
};


extern "C" {

void bone_transform( double current_time, animation* a, node* n, glm::mat4* transforms);
void read_node_heirachy(float animation_time, animation* a, node* n, glm::mat4 parent_transform, glm::mat4* transforms);

void matrix_inverse(glm::mat4* in, glm::mat4* out);
void matrix_to_normal_matrix(glm::mat4* in, glm::mat4* out);

void test_sphere(float _radius  ,int _segmentsW ,int _segmentsH);

}
#endif
