module Sequel
  module Schema
    module SQL
      AUTOINCREMENT = 'AUTOINCREMENT'.freeze
      CASCADE = 'CASCADE'.freeze
      COMMA_SEPARATOR = ', '.freeze
      NO_ACTION = 'NO ACTION'.freeze
      NOT_NULL = ' NOT NULL'.freeze
      NULL = ' NULL'.freeze
      PRIMARY_KEY = ' PRIMARY KEY'.freeze
      RESTRICT = 'RESTRICT'.freeze
      SET_DEFAULT = 'SET DEFAULT'.freeze
      SET_NULL = 'SET NULL'.freeze
      TYPES = Hash.new {|h, k| k}
      TYPES[:double] = 'double precision'
      UNDERSCORE = '_'.freeze
      UNIQUE = ' UNIQUE'.freeze
      UNSIGNED = ' UNSIGNED'.freeze

      # The SQL to execute to modify the DDL for the given table name.  op
      # should be one of the operations returned by the AlterTableGenerator.
      def alter_table_sql(table, op)
        quoted_table = quote_identifier(table)
        quoted_name = quote_identifier(op[:name]) if op[:name]
        alter_table_op = case op[:op]
        when :add_column
          "ADD COLUMN #{column_definition_sql(op)}"
        when :drop_column
          "DROP COLUMN #{quoted_name}"
        when :rename_column
          "RENAME COLUMN #{quoted_name} TO #{quote_identifier(op[:new_name])}"
        when :set_column_type
          "ALTER COLUMN #{quoted_name} TYPE #{op[:type]}"
        when :set_column_default
          "ALTER COLUMN #{quoted_name} SET DEFAULT #{literal(op[:default])}"
        when :add_index
          return index_definition_sql(table, op)
        when :drop_index
          return drop_index_sql(table, op)
        when :add_constraint
          "ADD #{constraint_definition_sql(op)}"
        when :drop_constraint
          "DROP CONSTRAINT #{quoted_name}"
        else
          raise Error, "Unsupported ALTER TABLE operation"
        end
        "ALTER TABLE #{quoted_table} #{alter_table_op}"
      end

      # Array of SQL DDL modification statements for the given table,
      # corresponding to the DDL changes specified by the operations.
      def alter_table_sql_list(table, operations)
        operations.map{|op| alter_table_sql(table, op)}
      end
      
      # The SQL string specify the autoincrement property, generally used by
      # primary keys.
      def auto_increment_sql
        AUTOINCREMENT
      end
      
      # SQL DDL fragment containing the column creation SQL for the given column.
      def column_definition_sql(column)
        return constraint_definition_sql(column) if column[:type] == :check
        sql = "#{quote_identifier(column[:name])} #{type_literal(column)}"
        sql << UNIQUE if column[:unique]
        sql << NOT_NULL if column[:null] == false
        sql << NULL if column[:null] == true
        sql << " DEFAULT #{literal(column[:default])}" if column.include?(:default)
        sql << PRIMARY_KEY if column[:primary_key]
        sql << " #{auto_increment_sql}" if column[:auto_increment]
        sql << column_references_sql(column) if column[:table]
        sql
      end
      
      # SQL DDL fragment containing the column creation
      # SQL for all given columns, used instead a CREATE TABLE block.
      def column_list_sql(columns)
        columns.map{|c| column_definition_sql(c)}.join(COMMA_SEPARATOR)
      end

      # SQL DDL fragment for column foreign key references
      def column_references_sql(column)
        sql = " REFERENCES #{quote_identifier(column[:table])}"
        sql << "(#{Array(column[:key]).map{|x| quote_identifier(x)}.join(COMMA_SEPARATOR)})" if column[:key]
        sql << " ON DELETE #{on_delete_clause(column[:on_delete])}" if column[:on_delete]
        sql << " ON UPDATE #{on_delete_clause(column[:on_update])}" if column[:on_update]
        sql
      end
    
      # SQL DDL fragment specifying a constraint on a table.
      def constraint_definition_sql(constraint)
        sql = constraint[:name] ? "CONSTRAINT #{quote_identifier(constraint[:name])} " : ""
        case constraint[:constraint_type]
        when :primary_key
          sql << "PRIMARY KEY #{literal(constraint[:columns])}"
        when :foreign_key
          sql << "FOREIGN KEY #{literal(constraint[:columns])}"
          sql << column_references_sql(constraint)
        when :unique
          sql << "UNIQUE #{literal(constraint[:columns])}"
        else
          sql << "CHECK #{filter_expr(constraint[:check])}"
        end
        sql
      end

      # Array of SQL DDL statements, the first for creating a table with the given
      # name and column specifications, and the others for specifying indexes on
      # the table.
      def create_table_sql_list(name, columns, indexes = nil)
        sql = ["CREATE TABLE #{quote_identifier(name)} (#{column_list_sql(columns)})"]
        sql.concat(index_list_sql_list(name, indexes)) if indexes && !indexes.empty?
        sql
      end
      
      # Default index name for the table and columns, may be too long
      # for certain databases.
      def default_index_name(table_name, columns)
        "#{table_name}_#{columns.join(UNDERSCORE)}_index"
      end
    
      # The SQL to drop an index for the table.
      def drop_index_sql(table, op)
        "DROP INDEX #{quote_identifier(op[:name] || default_index_name(table, op[:columns]))}"
      end

      # SQL DDL statement to drop the table with the given name.
      def drop_table_sql(name)
        "DROP TABLE #{quote_identifier(name)}"
      end
      
      # Proxy the filter_expr call to the dataset, used for creating constraints.
      def filter_expr(*args, &block)
        schema_utility_dataset.literal(schema_utility_dataset.send(:filter_expr, *args, &block))
      end

      # SQL DDL statement for creating an index for the table with the given name
      # and index specifications.
      def index_definition_sql(table_name, index)
        index_name = index[:name] || default_index_name(table_name, index[:columns])
        if index[:type]
          raise Error, "Index types are not supported for this database"
        elsif index[:where]
          raise Error, "Partial indexes are not supported for this database"
        else
          "CREATE #{'UNIQUE ' if index[:unique]}INDEX #{quote_identifier(index_name)} ON #{quote_identifier(table_name)} #{literal(index[:columns])}"
        end
      end
    
      # Array of SQL DDL statements, one for each index specification,
      # for the given table.
      def index_list_sql_list(table_name, indexes)
        indexes.map{|i| index_definition_sql(table_name, i)}
      end
  
      # Proxy the literal call to the dataset, used for default values.
      def literal(v)
        schema_utility_dataset.literal(v)
      end
      
      # SQL DDL ON DELETE fragment to use, based on the given action.
      # The following actions are recognized:
      # 
      # * :cascade - Delete rows referencing this row.
      # * :no_action (default) - Raise an error if other rows reference this
      #   row, allow deferring of the integrity check.
      # * :restrict - Raise an error if other rows reference this row,
      #   but do not allow deferring the integrity check.
      # * :set_default - Set columns referencing this row to their default value.
      # * :set_null - Set columns referencing this row to NULL.
      def on_delete_clause(action)
        case action
        when :restrict
          RESTRICT
        when :cascade
          CASCADE
        when :set_null
          SET_NULL
        when :set_default
          SET_DEFAULT
        else
          NO_ACTION
        end
      end
      
      # Proxy the quote_identifier method to the dataset, used for quoting tables and columns.
      def quote_identifier(v)
        schema_utility_dataset.quote_identifier(v)
      end
      
      # SQL DDL statement for renaming a table.
      def rename_table_sql(name, new_name)
        "ALTER TABLE #{quote_identifier(name)} RENAME TO #{quote_identifier(new_name)}"
      end

      # Parse the schema from the database using the SQL standard INFORMATION_SCHEMA.
      # If the table_name is not given, returns the schema for all tables as a hash.
      # If the table_name is given, returns the schema for a single table as an
      # array with all members being arrays of length 2.  Available options are:
      #
      # * :reload - Get fresh information from the database, instead of using
      #   cached information.  If table_name is blank, :reload should be used
      #   unless you are sure that schema has not been called before with a
      #   table_name, otherwise you may only getting the schemas for tables
      #   that have been requested explicitly.
      def schema(table_name = nil, opts={})
        if opts[:reload] && @schemas
          if table_name
            @schemas.delete(table_name)
          else
            @schemas = nil
          end
        end

        if table_name
          return @schemas[table_name] if @schemas && @schemas[table_name]
        else
          return @schemas if @schemas
        end

        if table_name
          @schemas ||= {}
          @schemas[table_name] ||= schema_parse_table(table_name, opts)
        else
          @schemas = schema_parse_tables(opts)
        end
      end
      
      # The dataset to use for proxying certain schema methods.
      def schema_utility_dataset
        @schema_utility_dataset ||= dataset
      end
      

      private

      # Match the database's column type to a ruby type via a
      # regular expression.  The following ruby types are supported:
      # integer, string, date, datetime, boolean, and float.
      def schema_column_type(db_type)
        case db_type
        when 'tinyint'
          Sequel.convert_tinyint_to_bool ? :boolean : :integer
        when /\A(int(eger)?|bigint|smallint)\z/
          :integer
        when /\A(character( varying)?|varchar|text)\z/
          :string
        when /\Adate\z/
          :date
        when /\A(datetime|timestamp( with(out)? time zone)?)\z/
          :datetime
        when /\Atime( with(out)? time zone)?\z/
          :time
        when "boolean"
          :boolean
        when /\A(real|float|double( precision)?)\z/
          :float
        when /\A(numeric|decimal|money)\z/
          :decimal
        when "bytea"
          :blob
        end
      end

      # The final dataset used by the schema parser, after all
      # options have been applied.
      def schema_ds(table_name, opts)
        schema_ds_dataset.from(*schema_ds_from(table_name, opts)) \
          .select(*schema_ds_select(table_name, opts)) \
          .join(*schema_ds_join(table_name, opts)) \
          .filter(*schema_ds_filter(table_name, opts))
      end

      # The blank dataset used by the schema parser.
      def schema_ds_dataset
        schema_utility_dataset
      end

      # Argument array for the schema dataset's filter method.
      def schema_ds_filter(table_name, opts)
        if table_name
          [{:c__table_name=>table_name.to_s}]
        else
          [{:t__table_type=>'BASE TABLE'}]
        end
      end

      # Argument array for the schema dataset's from method.
      def schema_ds_from(table_name, opts)
        [:information_schema__tables___t]
      end

      # Argument array for the schema dataset's join method.
      def schema_ds_join(table_name, opts)
        [:information_schema__columns, [:table_catalog, :table_schema, :table_name], :c]
      end

      # Argument array for the schema dataset's select method.
      def schema_ds_select(table_name, opts)
        cols = [:column_name___column, :data_type___db_type, :character_maximum_length___max_chars, \
          :numeric_precision, :column_default___default, :is_nullable___allow_null]
        cols << :c__table_name unless table_name
        cols
      end

      # Parse the schema for a given table.
      def schema_parse_table(table_name, opts)
        schema_parse_rows(schema_ds(table_name, opts))
      end

      # Parse the schema all tables in the database.
      def schema_parse_tables(opts)
        schemas = {}
        schema_ds(nil, opts).each do |row|
          (schemas[row.delete(:table_name).to_sym] ||= []) << row
        end
        schemas.each do |table, rows|
          schemas[table] = schema_parse_rows(rows)
        end
        schemas
      end

      # Parse the output of the information schema columns into
      # the hash used by Sequel.
      def schema_parse_rows(rows)
        schema = []
        rows.each do |row| 
          row[:allow_null] = row[:allow_null] == 'YES' ? true : false
          row[:default] = nil if row[:default].blank?
          row[:type] = schema_column_type(row[:db_type])
          schema << [row.delete(:column).to_sym, row]
        end
        schema
      end

      # SQL fragment specifying the type of a given column.
      def type_literal(column)
        column[:size] ||= 255 if column[:type] == :varchar
        elements = column[:size] || column[:elements]
        "#{type_literal_base(column)}#{literal(Array(elements)) if elements}#{UNSIGNED if column[:unsigned]}"
      end

      # SQL fragment specifying the base type of a given column,
      # without the size or elements.
      def type_literal_base(column)
        TYPES[column[:type]]
      end
    end
  end
end
