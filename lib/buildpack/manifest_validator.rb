require 'kwalify'
require 'kwalify/parser/yaml-patcher'
require 'uri'

module Buildpack
  class ManifestValidator
    class ManifestValidationError < StandardError; end

    SCHEMA_FILE = File.join(File.dirname(__FILE__), 'packager', 'manifest_schema.yml')

    attr_reader :errors

    def initialize(manifest_path)
      @manifest_path = manifest_path
    end

    def valid?
      validate
      errors.empty?
    end

    private

    def validate
      schema = Kwalify::Yaml.load_file(SCHEMA_FILE)
      validator = Kwalify::Validator.new(schema)
      parser = Kwalify::Yaml::Parser.new(validator)
      manifest_data = parser.parse_file(@manifest_path)
      validate_default_versions(manifest_data) if manifest_data["default_versions"]

      @errors = {}
      @errors[:manifest_parser_errors] = parser.errors unless parser.errors.empty?
    end

    def validate_default_versions(manifest_data)
      default_versions = manifest_data["default_versions"]
      default_dependency_names = default_versions.map { |dep| dep['name'] }
      dependencies = manifest_data["dependencies"]
      dependency_names = dependencies.map { |dep| dep['name'] }
      something_was_invalid = false
      error_messaging = []

      if has_duplicate_names?(default_dependency_names)
        something_was_invalid = true
        duplicates = default_dependency_names.find_all { |dep| default_dependency_names.count(dep) > 1 }.uniq
        duplicates.each do |duplicate|
          error_messaging << "- #{duplicate} had more than one 'default_versions' entry in the buildpack manifest."
        end
      end

      if dependency_name_not_found?(default_dependency_names, dependency_names)
        something_was_invalid = true
        missing_dependencies = missing_dependencies(default_dependency_names, dependency_names)
        missing_dependencies.each do |missing_dependency|
          error_messaging << "- a 'default_versions' entry for #{missing_dependency} was specified by the buildpack manifest, but no " +
                             "'dependencies' entry with the name #{missing_dependency} was found in the buildpack manifest."
        end
      end

      if dependency_version_not_found?(default_dependency_names, dependency_names)
        something_was_invalid = true
        default_dependency_names_in_dependencies = default_dependency_names - missing_dependencies(default_dependency_names, dependency_names)
        default_name_to_version_hash = Hash[default_dependencies.map {|dep| [dep['name'], dep['version']]}]
        default_dependency_names_in_dependencies.each do |dep_name|
          matched_dependencies = dependencies.select{ |dep| dep['name'] == dep_name }
          matched_dependencies.select { |dep| dep }
        end
        missing_dependency_versions = {}
        STDERR.puts "The buildpack manifest is malformed: a 'default_versions' entry " +
                    "#{} was specified by the buildpack manifest, but no 'dependencies' entries " +
                    "for #{} were found in the buildpack manifest."
      end

      if something_was_invalid
        error_messaging.unshift("The buildpack manifest is malformed:")
        error_messaging << "For more information, see " +
                           "https://docs.cloudfoundry.org/buildpacks/custom.html#specifying-default-versions"
        STDERR.puts error_messaging.join("\n")
        exit 1
      end
    end

    def has_duplicate_names?(default_dependency_names)
      default_dependency_names.length != default_dependency_names.uniq.length
    end

    def missing_dependencies(default_dependency_names, dependency_names)
      default_dependency_names - dependency_names
    end

    def dependency_name_not_found?(default_dependency_names, dependency_names)
      !(default_dependency_names - dependency_names).empty?
    end

    def dependency_version_not_found?(default_dependencies, dependencies)
     deps_match = default_dependencies.map do |default_dependency|
        default_name = default_dependency['name']
        default_version = default_dependency['version']
        matched_dependencies = dependencies.select{ |dep| dep['name'] == default_name }
        matched = matched_dependencies.find {|dep| dep['version'] == default_version}
        !matched.nil?
     end
     deps_match.all?
    end
  end
end
class DependencySet
  attr_accessor :dependencies
  def initialize(dependencies)
    @dependencies = dependencies
  end
end

class Dependency
  attr_accessor :name
  attr_accessor :version

  def initialize(name, version)
    @name = name
    @version = version
  end
end
