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

require 'api/object'
require 'google/string_utils'

module Api
  # Represents a property type
  class Type < Api::Object::Named
    # The list of properties (attr_reader) that can be overridden in
    # <provider>.yaml.
    module Fields
      include Api::Object::Named::Properties

      attr_reader :default_value
      attr_reader :description
      attr_reader :exclude

      # Add a deprecation message for a field that's been deprecated in the API
      # use the YAML chomping folding indicator (>-) if this is a multiline
      # string, as providers expect a single-line one w/o a newline.
      attr_reader :deprecation_message

      attr_reader :output # If set value will not be sent to server on sync
      attr_reader :input # If set to true value is used only on creation
      attr_reader :url_param_only # If, true will not be send in request body
      attr_reader :required
      attr_reader :update_verb
      attr_reader :update_url
      # If true, we will include the empty value in requests made including
      # this attribute (both creates and updates).  This rarely needs to be
      # set to true, and corresponds to both the "NullFields" and
      # "ForceSendFields" concepts in the autogenerated API clients.
      attr_reader :send_empty_value
      attr_reader :min_version

      # A list of properties that conflict with this property.
      attr_reader :conflicts

      # Can only be overriden - we should never set this ourselves.
      attr_reader :new_type
    end

    include Fields

    attr_reader :__resource
    attr_reader :__parent # is nil for top-level properties

    MAX_NAME = 20

    def validate
      super
      check :description, type: ::String, required: true
      check :exclude, type: :boolean, default: false, required: true
      check :deprecation_message, type: ::String
      check :min_version, type: ::String
      check :output, type: :boolean
      check :required, type: :boolean
      check :url_param_only, type: :boolean

      raise 'Property cannot be output and required at the same time.' \
        if @output && @required

      check :update_verb, type: Symbol, allowed: %i[POST PUT PATCH NONE],
                          default: @__resource&.update_verb

      check :update_url, type: ::String

      check_default_value_property
      check_conflicts
    end

    def to_s
      JSON.pretty_generate(self)
    end

    # Prints a dot notation path to where the field is nested within the parent
    # object. eg: parent.meta.label.foo
    # The only intended purpose is to allow better error messages. Some objects
    # and at some points in the build this doesn't ouput a valid output.
    def lineage
      return name if __parent.nil?

      __parent.lineage + '.' + name
    end

    def to_json(opts = nil)
      # ignore fields that will contain references to parent resources and
      # those which will be added later
      ignored_fields = %i[@resource @__parent @__resource @api_name @update_verb
                          @__name @name @properties]
      json_out = {}

      instance_variables.each do |v|
        if v == :@conflicts && instance_variable_get(v).empty?
          # ignore empty conflict arrays
        elsif instance_variable_get(v) == false || instance_variable_get(v).nil?
          # ignore false booleans as non-existence indicates falsey
        elsif !ignored_fields.include? v
          json_out[v] = instance_variable_get(v)
        end
      end

      # convert properties to a hash based on name for nested readability
      json_out.merge!(properties&.map { |p| [p.name, p] }.to_h) \
        if respond_to? 'properties'

      JSON.generate(json_out, opts)
    end

    def check_default_value_property
      return if @default_value.nil?

      case self
      when Api::Type::String
        clazz = ::String
      when Api::Type::Integer
        clazz = ::Integer
      when Api::Type::Double
        clazz = ::Float
      when Api::Type::Enum
        clazz = ::Symbol
      when Api::Type::Boolean
        clazz = :boolean
      when Api::Type::ResourceRef
        clazz = [::String, ::Hash]
      else
        raise "Update 'check_default_value_property' method to support " \
              "default value for type #{self.class}"
      end

      check :default_value, type: clazz
    end

    # Checks that all conflicting properties actually exist.
    def check_conflicts
      check :conflicts, type: ::Array, default: [], item_type: ::String

      return if @conflicts.empty?

      names = @__resource.all_user_properties.map(&:api_name) +
              @__resource.all_user_properties.map(&:name)
      @conflicts.each do |p|
        raise "#{p} does not exist" unless names.include?(p)
      end
    end

    # Returns list of properties that are in conflict with this property.
    def conflicting
      return [] unless @__resource

      (@__resource.all_user_properties.select { |p| @conflicts.include?(p.api_name) } +
       @__resource.all_user_properties.select { |p| p.conflicts.include?(@api_name) }).uniq
    end

    def type
      self.class.name.split('::').last
    end

    def parent
      @__parent
    end

    def min_version
      if @min_version.nil?
        @__resource.min_version
      else
        @__resource.__product.version_obj(@min_version)
      end
    end

    def exclude_if_not_in_version!(version)
      @exclude ||= version < min_version
    end

    # Overriding is_a? to enable class overrides.
    # Ruby does not let you natively change types, so this is the next best
    # thing.
    def is_a?(clazz)
      return Module.const_get(@new_type).new.is_a?(clazz) if @new_type

      super(clazz)
    end

    # Overriding class to enable class overrides.
    # Ruby does not let you natively change types, so this is the next best
    # thing.
    def class
      return Module.const_get(@new_type) if @new_type

      super
    end

    # Returns nested properties for this property.
    def nested_properties
      []
    end

    def nested_properties?
      !nested_properties.empty?
    end

    def deprecated?
      !(@deprecation_message.nil? || @deprecation_message == '')
    end

    private

    # A constant value to be provided as field
    class Constant < Type
      attr_reader :value

      def validate
        @description = "This is always #{value}."
        super
      end
    end

    # Represents a primitive (non-composite) type.
    class Primitive < Type
    end

    # Represents a boolean
    class Boolean < Primitive
    end

    # Represents an integer
    class Integer < Primitive
    end

    # Represents a double
    class Double < Primitive
    end

    # Represents a string
    class String < Primitive
      def initialize(name = nil)
        @name = name
      end

      PROJECT = Api::Type::String.new('project')
      NAME = Api::Type::String.new('name')
    end

    # Properties that are fetched externally
    class FetchedExternal < Type
      attr_writer :resource

      def validate
        @conflicts ||= []
      end

      def api_name
        name
      end
    end

    class Path < Primitive
    end

    # Represents a fingerprint.  A fingerprint is an output-only
    # field used for optimistic locking during updates.
    # They are fetched from the GCP response.
    class Fingerprint < FetchedExternal
      def validate
        super
        @output = true if @output.nil?
      end
    end

    # Represents a timestamp
    class Time < Primitive
    end

    # A base class to tag objects that are composed by other objects (arrays,
    # nested objects, etc)
    class Composite < Type
    end

    # Forwarding declaration to allow defining Array::NESTED_ARRAY_TYPE
    class NestedObject < Composite
    end

    # Forwarding declaration to allow defining Array::RREF_ARRAY_TYPE
    class ResourceRef < Type
    end

    # Represents an array, and stores its items' type
    class Array < Composite
      attr_reader :item_type
      attr_reader :min_size
      attr_reader :max_size

      def validate
        super
        if @item_type.is_a?(NestedObject) || @item_type.is_a?(ResourceRef)
          @item_type.set_variable(@name, :__name)
          @item_type.set_variable(@__resource, :__resource)
          @item_type.set_variable(self, :__parent)
        end
        check :item_type, type: [::String, NestedObject, ResourceRef, Enum], required: true

        unless @item_type.is_a?(NestedObject) || @item_type.is_a?(ResourceRef) \
            || @item_type.is_a?(Enum) || type?(@item_type)
          raise "Invalid type #{@item_type}"
        end

        check :min_size, type: ::Integer
        check :max_size, type: ::Integer
      end

      def property_class
        if @item_type.is_a?(NestedObject) || @item_type.is_a?(ResourceRef)
          type = @item_type.property_class
        elsif @item_type.is_a?(Enum)
          raise 'aaaa'
        else
          type = property_ns_prefix
          type << get_type(@item_type).new(@name).type
        end
        type[-1] = "#{type[-1].camelize(:upper)}Array"
        type
      end

      def exclude_if_not_in_version!(version)
        super
        @item_type.exclude_if_not_in_version!(version) \
          if @item_type.is_a? NestedObject
      end

      def nested_properties
        return @item_type.nested_properties.reject(&:exclude) \
          if @item_type.is_a?(Api::Type::NestedObject)

        super
      end
    end

    # Represents an enum, and store is valid values
    class Enum < Primitive
      attr_reader :values

      def validate
        super
        check :values, type: ::Array, item_type: [Symbol, ::String, ::Integer], required: true
      end
    end

    # Represents a 'selfLink' property, which returns the URI of the resource.
    class SelfLink < FetchedExternal
      EXPORT_KEY = 'selfLink'.freeze

      attr_reader :resource

      def name
        EXPORT_KEY
      end

      def out_name
        EXPORT_KEY.underscore
      end
    end

    # Represents a reference to another resource
    class ResourceRef < Type
      # The fields which can be overridden in provider.yaml.
      module Fields
        attr_reader :resource
        attr_reader :imports
      end
      include Fields

      def validate
        super
        @name = @resource if @name.nil?
        @description = "A reference to #{@resource} resource" \
          if @description.nil?

        return if @__resource.nil? || @__resource.exclude || @exclude

        check :resource, type: ::String, required: true
        check :imports, type: ::String, required: true
        check_resource_ref_exists
        check_resource_ref_property_exists
      end

      def property
        props = resource_ref.all_user_properties
                            .select { |prop| prop.name == @imports }
        return props.first unless props.empty?
        raise "#{@imports} does not exist on #{@resource}" if props.empty?
      end

      def resource_ref
        product = @__resource.__product
        resources = product.objects.select { |obj| obj.name == @resource }
        raise "Unknown item type '#{@resource}'" if resources.empty?

        resources[0]
      end

      def property_class
        type = property_ns_prefix
        type << [@resource, @imports, 'Ref']
        type[-1] = type[-1].join('_').camelize(:upper)
        type
      end

      private

      def check_resource_ref_exists
        product = @__resource.__product
        resources = product.objects.select { |obj| obj.name == @resource }
        raise "Missing '#{@resource}'" if resources.empty?
      end

      def check_resource_ref_property_exists
        exported_props = resource_ref.all_user_properties
        exported_props << Api::Type::String.new('selfLink') \
          if resource_ref.has_self_link
        raise "'#{@imports}' does not exist on '#{@resource}'" \
          if exported_props.none? { |p| p.name == @imports }
      end
    end

    # An structured object composed of other objects.
    class NestedObject < Composite
      # A custom getter is used for :properties instead of `attr_reader`

      def validate
        @description = 'A nested object resource' if @description.nil?
        @name = @__name if @name.nil?
        super

        raise "Properties missing on #{name}" if @properties.nil?

        @properties.each do |p|
          p.set_variable(@__resource, :__resource)
          p.set_variable(self, :__parent)
        end
        check :properties, type: ::Array, item_type: Api::Type, required: true
      end

      def property_class
        type = property_ns_prefix
        type << [@__resource.name, @name]
        type[-1] = type[-1].join('_').camelize(:upper)
        type
      end

      # Returns all properties including the ones that are excluded
      # This is used for PropertyOverride validation
      def all_properties
        @properties
      end

      def properties
        raise "Field '#{lineage}' properties are nil!" if @properties.nil?

        @properties.reject(&:exclude)
      end

      def nested_properties
        properties
      end

      # Returns the list of top-level properties once any nested objects with
      # flatten_object set to true have been collapsed
      def root_properties
        properties.flat_map do |p|
          if p.flatten_object
            p.root_properties
          else
            p
          end
        end
      end

      def exclude_if_not_in_version!(version)
        super
        @properties.each { |p| p.exclude_if_not_in_version!(version) }
      end
    end

    # An array of string -> string key -> value pairs, such as labels.
    # While this is technically a map, it's split out because it's a much
    # simpler property to generate and means we can avoid conditional logic
    # in Map.
    class KeyValuePairs < Composite
    end

    # Map from string keys -> nested object entries
    class Map < Composite
      # The list of properties (attr_reader) that can be overridden in
      # <provider>.yaml.
      module Fields
        # The type definition of the contents of the map.
        attr_reader :value_type

        # While the API doesn't give keys an explicit name, we specify one
        # because in Terraform the key has to be a property of the object.
        #
        # The name of the key. Used in the Terraform schema as a field name.
        attr_reader :key_name

        # A description of the key's format. Used in Terraform to describe
        # the field in documentation.
        attr_reader :key_description
      end
      include Fields

      def validate
        super
        check :key_name, type: ::String, required: true
        check :key_description, type: ::String

        @value_type.set_variable(@name, :__name)
        @value_type.set_variable(@__resource, :__resource)
        @value_type.set_variable(self, :__parent)
        check :value_type, type: Api::Type::NestedObject, required: true
        raise "Invalid type #{@value_type}" unless type?(@value_type)
      end

      def nested_properties
        @value_type.nested_properties.reject(&:exclude)
      end
    end

    def type?(type)
      type.is_a?(Type) || !get_type(type).nil?
    end

    def get_type(type)
      Module.const_get(type)
    end

    def property_ns_prefix
      [
        'Google',
        @__resource.__product.name.camelize(:upper),
        'Property'
      ]
    end
  end
end
