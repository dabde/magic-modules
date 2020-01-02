# Copyright 2017 Google Inc.
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

require 'overrides/resources'

module Overrides
  module Inspec
    # A class to control overridden properties on inspec.yaml in lieu of
    # values from api.yaml.
    class ResourceOverride < Overrides::ResourceOverride
      def self.attributes
        %i[
          manual
          additional_functions
          product_url
          privileged
          singular_only
          singular_extra_examples
        ]
      end

      attr_reader(*attributes)

      def validate
        check :manual, type: :boolean, default: false
        super
        check :additional_functions, type: String
        check :product_url, type: String
        # true if the resources requires organization level privileges
        # resource manager Folder is an example of a privileged resource
        check :privileged, type: :boolean, default: false
        check :singular_only, type: :boolean, default: false
        # Points to a markdown file with extra examples to include in documentation
        check :singular_extra_examples, type: String
      end
    end
  end
end
