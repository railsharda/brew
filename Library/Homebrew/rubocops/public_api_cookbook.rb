# typed: strict
# frozen_string_literal: true

require "rubocops/shared/api_annotation_helper"

module RuboCop
  module Cop
    module Homebrew
      # Ensures that methods and DSL calls documented in the Formula Cookbook
      # or Cask Cookbook are annotated with `@api public` in their source
      # definitions.
      #
      # Both cookbook method lists live in {ApiAnnotationHelper} and are
      # validated by CI to stay in sync with the source `@api` annotations.
      class PublicApiCookbook < Base
        MSG = "Method `%<method>s` is referenced in the %<cookbook>s but is not annotated with `@api public`."

        sig { void }
        def on_new_investigation
          super

          file_path = processed_source.file_path
          return if file_path.nil?

          relative_path = file_path.sub(%r{.*/Library/Homebrew/}, "")

          api_public_lines = Set.new
          processed_source.comments.each do |comment|
            text = comment.text.strip
            api_public_lines.add(comment.loc.line) if ["# @api public", "@api public"].include?(text)
          end

          check_cookbook_methods(ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS,
                                 "Formula Cookbook", relative_path, api_public_lines)
          check_cookbook_methods(ApiAnnotationHelper::CASK_COOKBOOK_METHODS,
                                 "Cask Cookbook", relative_path, api_public_lines)
        end

        private

        sig {
          params(
            cookbook_methods: T::Hash[String, String],
            cookbook_name:    String,
            relative_path:    String,
            api_public_lines: T::Set[Integer],
          ).void
        }
        def check_cookbook_methods(cookbook_methods, cookbook_name, relative_path, api_public_lines)
          relevant_methods = cookbook_methods.select { |_, file| file == relative_path }
          return if relevant_methods.empty?

          method_names = relevant_methods.keys.to_set

          processed_source.ast&.each_descendant(:def, :defs, :send) do |node|
            method_name = case node.type
            when :def, :defs
              node.method_name.to_s
            when :send
              next unless [:attr_reader, :attr_accessor].include?(node.method_name)

              node.arguments.each do |arg|
                next unless arg.sym_type?

                attr_name = arg.value.to_s
                next unless method_names.include?(attr_name)
                next if api_public_annotation_near?(node, api_public_lines)

                add_offense(node,
                            message: format(MSG, method: attr_name, cookbook: cookbook_name))
              end
              next
            end

            next if method_name.nil?
            next unless method_names.include?(method_name)
            next if api_public_annotation_near?(node, api_public_lines)

            add_offense(node, message: format(MSG, method: method_name, cookbook: cookbook_name))
          end
        end

        sig { params(node: RuboCop::AST::Node, api_public_lines: T::Set[Integer]).returns(T::Boolean) }
        def api_public_annotation_near?(node, api_public_lines)
          node_line = node.loc.line
          (([node_line - 20, 1].max)...node_line).any? { |line| api_public_lines.include?(line) }
        end
      end
    end
  end
end
