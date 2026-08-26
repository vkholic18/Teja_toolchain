my_schema = {
    'version': {'type': 'string'},
    'external_services': {'type': 'list', 'nullable': True,
                          'schema': {
                              'type': 'dict', 'schema':
                                  {
                                      'name': {'type': 'string', 'required': True},
                                      'apis': {'type': 'list', 'schema': {'type': 'string'}}
                                  }
                          }
                          },
    'workspaces': {'type': 'list', 'nullable': True,
                   'schema': {
                       'type': 'dict', 'schema':
                           {
                               'name': {'type': 'string', 'required': True},
                               'version': {'type': 'string', 'required': True},
                               'feature_flag': {'type': 'string', 'required': True},
                               'rest': {'type': 'list', 'schema': {'type': 'string'}},
                               'grpc': {'type': 'list', 'schema': {'type': 'string'}},
                               'objects': {'type': 'list', 'schema': {'type': 'string'}},
                               'packages': {'type': 'list', 'schema': {'type': 'string'}},
                               'events': {'type': 'list', 'schema': {'type': 'string'}},
                               'other': {'type': 'list', 'schema': {
                                   'type': 'dict', 'schema': {
                                       'dep_type': {'type': 'string'},
                                       'dependency': {'type': 'string'}
                                   }
                               }
                                         }
                           }
                   }
                   }

}