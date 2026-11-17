# O TLS registra avisos a cada handshake recusado; os testes os provocam de propósito.
:logger.set_application_level(:ssl, :error)
ExUnit.start()
