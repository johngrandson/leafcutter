# Definition of Done

Uma mudança está concluída quando:

- comportamento foi implementado no owner context;
- API pública e tipos são previsíveis;
- nenhum internal boundary foi violado;
- testes cobrem happy path e falhas relevantes;
- formatter/compile/tests passam;
- docs in-code estão em inglês;
- arquitetura externa está atualizada quando impactada;
- OpenAPI foi atualizado quando a API mudou;
- migrations/rollback foram avaliados;
- dados sensíveis não vazam;
- checkpoint de sessão foi atualizado em marcos;
- diff continua pequeno o suficiente para ser explicado.
