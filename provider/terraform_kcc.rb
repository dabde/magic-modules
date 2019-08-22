# Copyright 2019 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'provider/terraform'
require 'provider/terraform/import'

module Provider
  # Magic Modules Provider for KCC ServiceMappings and other related templates.
  # Instead of generating KCC directly, this provider generates a KCC-compatible
  # library to be consumed by KCC.
  class TerraformKCC < Provider::Terraform

    def generate(output_folder, types, version_name, product_path, dump_yaml)
      compile_product_files(output_folder, version_name)
    end

    def compile_product_files(output_folder, version_name)
      file_template = ProductFileTemplate.new(
        output_folder,
        nil,
        @api,
        version_name,
        build_env
      )
      compile_file_list(output_folder,
                        [
                          ["servicemappings/#{@api.name.downcase}_gen.yaml", 'templates/kcc/service_mapping.yaml.erb'],
                        ],
                        file_template)
    end

    def compile_common_files(output_folder, version_name, products, _common_compile_file)
      Google::LOGGER.info 'Compiling common files.'
      file_template = ProviderFileTemplate.new(
        output_folder,
        version_name,
        build_env,
        products
      )
      compile_file_list(output_folder, [], file_template)
    end

    def copy_common_files(output_folder, _version_name)
      Google::LOGGER.info 'Copying common files.'
      copy_file_list(output_folder, [])
    end
  end
end
