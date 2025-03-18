#include <torch/csrc/jit/python/python_ivalue.h>

int main() {
  using torch::autograd::variable_list;
  auto vl = variable_list();
  (void)vl;

  return 0;
}
