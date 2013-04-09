def generate_padrino_handler_list
  @routes   = Registry.all(:padrino_route).sort
  @handlers = Registry.all(:padrino_handler).sort
  @list_title = 'Padrino Handler List'
  @list_type = 'padrino_handler'
  generate_list_contents
end
