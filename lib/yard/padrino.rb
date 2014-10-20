# -*- coding: utf-8 -*-
require 'yard/padrino/version'
require 'yard'

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

    YARD::Templates::Engine.register_template_path File.dirname(__FILE__) + '/../../templates'

    class RegexpObject
      def initialize(pattern)
        @pattern = pattern
      end

      def to_s
        @pattern
      end

      def inspect
        "(Regexp) #{@pattern}"
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

    class HandlerObject < YARD::CodeObjects::Base
      attr_accessor :verb
      attr_accessor :args
      attr_accessor :controller

      def initialize(namespace, name, *args, &block)
        super

        signature = display_name
      end

      def <=>(target)
        self.name <=> target.name
      end

      def display_name
        verb.to_s + " " + args.map { |p| p.inspect }.join(", ")
      end

      def self.method_name_for_handler(controller, verb, args)
        ([ controller, verb ] + args.map { |p| p.to_s.gsub(/[^\w_]/, '_') }).select { |i| ! i.nil? }.join('_')
      end
    end

    class GeneralHandlerObject < HandlerObject
      VERB_ORDER = {
        'before'  => 3,
        'after'   => 2,
        'error'   => 1,
      }

      def type
        :padrino_handler
      end

      def <=>(target)
        r = self.namespace.to_s <=> target.namespace.to_s
        return r if r != 0

        r = self.controller.to_s <=> target.controller.to_s
        return r if r != 0

        r = (VERB_ORDER[self.verb] || 0) <=> (VERB_ORDER[target.verb] || 0)
        return -r if r != 0

        r = self.args.to_s <=> target.args.to_s
        return r if r != 0

        return 0
      end
    end

    class RouteObject < HandlerObject
      VERB_ORDER = {
        'GET'     => 5,
        'POST'    => 4,
        'HEAD'    => 3,
        'PUT'     => 2,
        'DELETE'  => 1,
      }

      def type
        :padrino_route
      end

      def <=>(target)
        r = self.namespace.to_s <=> target.namespace.to_s
        return r if r != 0

        r = self.controller.to_s <=> target.controller.to_s
        return r if r != 0

        r = self.args.to_s <=> target.args.to_s
        return r if r != 0

        r = (VERB_ORDER[self.verb] || 0) <=> (VERB_ORDER[target.verb] || 0)
        return -r if r != 0

        return 0
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
          process_general_handler
        when :before, :after
          process_general_handler
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
        if is_literal?(param)
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

      def process_general_handler
        verb = statement.method_name(true).to_s
        paths = []

        statement.parameters(false).each do |param|
          if param.is_a? YARD::Parser::Ruby::LiteralNode
            paths << convert_literal(param)
          end
        end

        last_param = statement.parameters(false).last
        options = convert_hash(last_param)  if is_hash?(last_param)

        controller = extra_state.padrino[:controller]  if extra_state.padrino

        register_padrino_general_handler(controller, verb, paths, options)
      end

      def process_http_verb
        verb = statement.method_name(true).to_s.upcase
        paths = [ convert_literal(statement.parameters.first) ]

        last_param = statement.parameters(false).last
        options = convert_hash(last_param)  if is_hash?(last_param)

        controller = extra_state.padrino[:controller]  if extra_state.padrino

        register_padrino_route(controller, verb, paths, options)
      end

      def register_padrino_route(controller, verb, args, options = nil, &block)
        method_name = RouteObject.method_name_for_handler(controller, verb, args)

        register_padrino_handler(
          {
            :class        => RouteObject,
            :group        => "Padrino Routings",
            :method_name  => method_name,
            :controller   => controller,
            :verb         => verb,
            :args         => args,
            :options      => options,
          },
          &block
        )
      end

      def register_padrino_general_handler(controller, verb, args, options = nil, &block)
        method_name = GeneralHandlerObject.method_name_for_handler(controller, verb, args)
        method_name = method_name + '#' + method_name.object_id.to_s

        register_padrino_handler(
          {
            :class        => GeneralHandlerObject,
            :group        => "Padrino Handlers",
            :method_name  => method_name,
            :controller   => controller,
            :verb         => verb,
            :args         => args,
            :options      => options,
          },
          &block
        )
      end

      def register_padrino_handler(args = {}, &block)
        handler = args[:class].new(namespace, args[:method_name]) do |o|
          o.group        = args[:group]
          o.source       = statement.source
          o.docstring    = statement.comments
          o.add_file(parser.file, statement.line)

          o.controller = args[:controller]
          o.verb       = args[:verb]
          o.args       = args[:args]

          if args[:options]
            args[:options].each do |key, value|
              o.docstring.add_tag YARD::Tags::Tag.new(CONDITION_TAG, '+' + value.inspect + '+', nil, key.inspect)
            end
          end
        end

        block.call(handler) if block

        register handler
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

      def is_literal?(obj)
        return true if obj.is_a?(YARD::Parser::Ruby::LiteralNode)

        return false unless obj.is_a?(YARD::Parser::Ruby::AstNode)
        obj.type == :dyna_symbol
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

    module HtmlHelper
      include YARD::Templates::Helpers::MarkupHelper
      include YARD::Templates::Helpers::HtmlSyntaxHighlightHelper

      # Formats the signature of Padrino +route+.
      #
      # @param [RouteObject] route the routing object to list the signature of
      # @param [Boolean] link whether to link the method signature to the details view
      # @return [String] the formatted route signature
      def signature_for_padrino_handler(route, link = true)
        name = route.display_name
        blk = format_block(route)

        title = "<strong>%s</strong>%s" % [h(name), blk]
        if link
          link_title = h(name)
          obj = route.respond_to?(:object) ? route.object : route
          url = url_for(object, obj)
          link_url(url, title, :title => link_title)
        else
          title
        end
      end
    end

    YARD::Templates::Template.extra_includes << HtmlHelper
  end
end
