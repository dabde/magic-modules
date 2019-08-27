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
    def generate(output_folder, types, _product_path, _dump_yaml)
      @base_url = @version.base_url
      generate_objects(output_folder, types)
      compile_product_files(output_folder)
    end

    # Create a directory of samples per resource
    def generate_resource(data)
      examples = data.object.examples
                     .reject(&:skip_test)
                     .reject { |e| !e.test_env_vars.nil? && e.test_env_vars.any? }
                     .reject { |e| @version < @api.version_obj_or_closest(e.min_version) }

      examples.each do |example|
        target_folder = File.join(data.output_folder, 'samples', example.name)
        FileUtils.mkpath target_folder

        data.example = example

        data.generate(
          'templates/kcc/samples/sample.tf.erb',
          File.join(target_folder, 'main.tf'),
          self
        )
      end
    end

    def generate_resource_tests(data) end

    def generate_iam_policy(data) end

    def compile_product_files(output_folder)
      file_template = ProductFileTemplate.new(
        output_folder,
        nil,
        @api,
        @target_version_name,
        build_env
      )
      compile_file_list(output_folder,
                        [
                          [
                            "servicemappings/#{@api.name.downcase}.yaml",
                            'templates/kcc/product/service_mapping.yaml.erb'
                          ]
                        ],
                        file_template)
    end

    def compile_common_files(output_folder, products, _common_compile_file)
      Google::LOGGER.info 'Compiling common files.'
      file_template = ProviderFileTemplate.new(
        output_folder,
        @target_version_name,
        build_env,
        products
      )
      compile_file_list(output_folder, [
                          [
                            'common/resources.go',
                            'templates/kcc/controller_resources.go.erb'
                          ]
                        ], file_template)
    end

    def copy_common_files(output_folder)
      Google::LOGGER.info 'Copying common files.'
      copy_file_list(output_folder, [])
    end
  end
end
