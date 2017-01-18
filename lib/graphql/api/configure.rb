require "graphql/api/types"
require "graphql/api/helpers"
require "graphql/api/resolvers/model_find_query"
require "graphql/api/resolvers/model_list_query"
require "graphql/api/resolvers/query_object_query"
require "graphql/api/mutation_description"
require "graphql/api/query_description"

include GraphQL::Api::Helpers

module GraphQL::Api
  class Configure
    include Types

    def initialize
      @types = {} # maps simple types to graphql query types, not needed for mutations
      @graphql_objects = []
    end

    # Return the graphQL schema
    def schema
      @schema ||= GraphQL::Schema.define(query: graphql_query, mutation: graphql_mutation)
    end

    def with_defaults(commands: [], queries: [], models: [])
      (all_constants('queries') + queries).each do |query_class|
        query(query_class)
      end
      (all_constants('models') + models).each do |model_class|
        model(model_class)
      end
      (all_constants('commands') + commands).each do |command_class|
        command(command_class)
      end
    end

    def model(model, only: nil, args: {})
      if model < ActiveRecord::Base
        if only
          only.each do |method|
            send("model_#{method}", model)
          end
        else
          model_show(model, args: args)
          model_index(model, args: args)
          model_create(model)
          model_delete(model)
          model_update(model)
        end
      else
        with_model(model)
      end
    end

    def mutation_description(mutation_description)
      unless mutation_description.mutation_type?
        raise("Mutation must be called with a MutationDescription")
      end
      @graphql_objects << mutation_description
    end

    def query_description(query_description)
      unless query_description.query_type?
        raise("Mutation must be called with a MutationDescription")
      end
      @graphql_objects << query_description
    end

    def command(model, action: :perform, resolver: nil)
      raise("Action does not exist on #{model.name}") unless model.actions[action]

      mutation = command_mutation_type(model, action, resolver: resolver)
      @graphql_objects << MutationDescription.new(mutation)
    end

    def query(model, action: :execute, resolver: nil)
      raise("Action does not exist on #{model.name}") unless model.actions[action]

      returns = model.actions[action][:returns]
      args = model.actions[action][:args]

      if action == :execute
        name = model.name.camelize(:lower)
      else
        name = "#{action}#{model.name.camelize}"
      end

      type = graphql_type_for_object(returns, @types)
      resolver = resolver || Resolvers::QueryObjectQuery.new(model, action)
      @graphql_objects << QueryDescription.new(name, type, args, resolver)
    end

    def with_model(model, fields: {})
      query = @types[model]
      unless query
        query = model_query_type(model, fields: fields)
        @types[model] = query
      end
      query
    end

    def model_show(model, args: {}, fields: {})
      type = with_model(model, fields: fields)
      name = model.name.camelize(:lower)
      args[:id] = :id
      @graphql_objects << QueryDescription.new(name, type, args, Resolvers::ModelFindQuery.new(model))
    end

    def model_index(model, args = {})
      type = with_model(model).to_list_type
      name = model.name.camelize(:lower).pluralize
      @graphql_objects << QueryDescription.new(name, type, args, Resolvers::ModelListQuery.new(model))
    end

    def model_create(model, resolver: nil)
      mutation = model_mutation_create_type(model, resolver: resolver)
      @graphql_objects << MutationDescription.new(mutation)
    end

    def model_update(model, resolver: nil)
      mutation = model_mutation_update_type(model, resolver: resolver)
      @graphql_objects << MutationDescription.new(mutation)
    end

    def model_delete(model, resolver: nil)
      mutation = model_mutation_delete_type(model, resolver: resolver)
      @graphql_objects << MutationDescription.new(mutation)
    end

    def graphql_query(&block)
      graphql_objects = @graphql_objects
      GraphQL::ObjectType.define do
        name 'Query'
        description 'The query root for this schema'

        instance_eval(&block) if block

        graphql_objects.each do |object|
          unless object.query_type?
            next
          end

          field(object.name) do
            type object.type
            object.args.each do |arg, arg_type|
              argument arg, graphql_type_of(arg_type)
            end
            resolve object.resolver
          end
        end
      end
    end

    def graphql_mutation(&block)
      graphql_objects = @graphql_objects
      GraphQL::ObjectType.define do
        name 'Mutation'
        description 'The mutation root for this schema'

        instance_eval(&block) if block

        graphql_objects.each do |object|
          unless object.mutation_type?
            next
          end

          field(object.name, field: object.type.field)
        end
      end
    end

  end
end