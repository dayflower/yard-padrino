# -*- coding: utf-8 -*-
require 'yard/padrino/version'

module YARD
  class CLI::Stats
    # Statistics for Padrino Handlers
    def stats_for_padrino_handlers
      output "P) Handlers", *type_statistics(:padrino_handler)
    end

    # Statistics for Padrino Routes
    def stats_for_padrino_routes
      output "P) Routes", *type_statistics(:padrino_route)
    end
  end

  module Padrino
    CONDITION_TAG = :'padrino.condition'

    YARD::Tags::Library.define_tag("Conditions", CONDITION_TAG, :with_name)
    YARD::Tags::Library.visible_tags << CONDITION_TAG

    class RegexpObject
      def initialize(pattern)
        @pattern = pattern
      end

      def to_s
        @pattern
      end

      def inspect
        "(Regexp)#{@pattern}"
      end
    end

    class AsisObject
      def initialize(data)
        @data = data
      end

      def to_s
        @data
      end

      def inspect
        @data
      end
    end

    class HandlerObject < YARD::CodeObjects::MethodObject
      attr_accessor :real_name

      def name(prefix = false)
        return super unless show_real_name?
        prefix ? "#{sep}#{real_name}" : real_name.to_sym
      end

      def show_real_name?
        real_name && caller[1] =~ /`signature'/
      end

      def sep
        YARD::CodeObjects::ISEP
      end

      def type
        :padrino_handler
      end
    end

    class RouteObject < HandlerObject
      attr_accessor :http_verb, :http_paths

      def type
        :padrino_route
      end
    end

    class Handler < YARD::Handlers::Ruby::Base
      handles method_call(:helpers)
      handles method_call(:controllers)
      handles method_call(:controller)

      handles method_call(:before)
      handles method_call(:after)

      handles method_call(:error)

      [ :get, :post, :put, :delete, :head ].each do |verb|
        handles method_call(verb)
      end

      namespace_only

      def process
        case statement.method_name(true)
        when :helpers
          process_helpers
        when :controllers, :controller
          process_controllers
        when :error
          process_handler
        when :before, :after
          process_handler
        else
          process_http_verb
        end
      end

      def process_helpers
        name = statement.first.source.gsub(/\s/, '')
        if statement[1] == :'.'
          # Foo::Bar.helpers do ... end style
          klass = YARD::CodeObjects::ClassObject.new(namespace, name)
          register(klass)
        else
          # helpers do ... end style
          klass = namespace
        end

        parse_block(statement.last[1], :namespace => klass)
      end

      def process_controllers
        name = statement.first.source.gsub(/\s/, '')
        if statement[1] == :'.'
          # Foo::Bar.controllers :baz do ... end style
          klass = YARD::CodeObjects::ClassObject.new(namespace, name)
          register(klass)
        else
          # controllers :baz do ... end style
          klass = namespace
        end

        controller = nil
        param = statement.parameters.first
        if param.is_a? YARD::Parser::Ruby::LiteralNode
          controller = convert_literal(param)
        end

        extra_state.padrino ||= {}
        last_controller = extra_state.padrino[:controller]
        begin
          extra_state.padrino[:controller] = controller
          parse_block(statement.last[1], :namespace => klass)
        ensure
          extra_state.padrino[:controller] = last_controller
        end
      end

      def process_handler
        verb = statement.method_name(true).to_s
        paths = []

        statement.parameters(false).each do |param|
          if param.is_a? YARD::Parser::Ruby::LiteralNode
            paths << convert_literal(param)
          end
        end

        last_param = statement.parameters(false).last
        options = convert_hash(last_param)  if is_hash?(last_param)

        if extra_state.padrino && extra_state.padrino[:controller]
          paths.unshift extra_state.padrino[:controller]
        end

        register_padrino_handler(verb, paths, options)
      end

      def process_http_verb
        verb = statement.method_name(true).to_s.upcase
        paths = [ convert_literal(statement.parameters.first) ]

        last_param = statement.parameters(false).last
        options = convert_hash(last_param)  if is_hash?(last_param)

        if extra_state.padrino && extra_state.padrino[:controller]
          paths.unshift extra_state.padrino[:controller]
        end

        register_padrino_route(verb, paths, options)
      end

      def register_padrino_route(verb, paths, options = nil)
        method_name  = ([ verb ] + paths.map { |p| p.to_s.gsub(/[^\w_]/, '_') }).join('_')
        display_name = verb.to_s + " " + paths.map { |p| p.inspect }.join(", ")

        route = register RouteObject.new(namespace, method_name) do |o|
          o.visibility = 'public'
          o.explicit   = true
          o.scope      = scope

          o.group      = "Padrino Routings"
          o.source     = statement.source
          o.signature  = display_name
          o.docstring  = statement.comments
          o.http_verb  = verb
          o.http_paths = paths
          o.real_name  = display_name
          o.add_file(parser.file, statement.line)

          if options
            options.each do |key, value|
              o.docstring.add_tag YARD::Tags::Tag.new(CONDITION_TAG, '+' + value.inspect + '+', nil, key.inspect)
            end
          end
        end

        yield(route) if block_given?

        route
      end

      def register_padrino_handler(verb, paths, options = nil)
        method_name  = ([ verb ] + paths.map { |p| p.to_s.gsub(/[^\w_]/, '_') }).join('_')
        display_name = verb.to_s + " " + paths.map { |p| p.inspect }.join(", ")

        handler = register HandlerObject.new(namespace, method_name + '#' + method_name.object_id.to_s) do |o|
          o.visibility = 'private'
          o.explicit   = true
          o.scope      = scope

          o.group      = "Padrino Handlers"
          o.source     = statement.source
          #o.signature  = display_name
          o.signature  = o.object_id
          o.docstring  = statement.comments
          o.real_name  = display_name
          o.add_file(parser.file, statement.line)

          if options
            options.each do |key, value|
              o.docstring.add_tag YARD::Tags::Tag.new(CONDITION_TAG, '+' + value.inspect + '+', nil, key.inspect)
            end
          end
        end

        yield(handler) if block_given?

        handler
      end

      private

      def is_hash?(obj)
        return false unless obj.is_a?(YARD::Parser::Ruby::AstNode)
        obj.type == :list && obj.first.type == :assoc
      end

      def convert_hash(hash)
        result = {}
        return result unless hash.type == :list

        hash.children.each do |obj|
          next unless obj.type == :assoc

          begin
            key   = convert_literal(obj.children[0])
            begin
              value = convert_literal(obj.children[1])
            rescue YARD::Parser::UndocumentableError
              value = AsisObject.new(obj.children[1].source)
            end

            result[key] = value
          rescue YARD::Parser::UndocumentableError
            # skip
          end
        end

        return result
      end

      def convert_literal(obj)
        case obj.type
        when :label
          obj.source.to_s.sub(/:$/, "").to_sym
        when :symbol_literal
          obj.jump(:ident, :op, :kw, :const).source.to_s.to_sym
        when :dyna_symbol
          obj.jump(:tstring_content).source.to_s.to_sym
        when :string_literal
          obj.jump(:string_content).source.to_s
        when :regexp_literal
          RegexpObject.new(obj.source)
        when :int
          obj.source.to_i
        else
          raise YARD::Parser::UndocumentableError, obj.source
        end
      end
    end
  end
end
