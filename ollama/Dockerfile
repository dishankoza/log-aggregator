FROM ollama/ollama

COPY start-ollama.sh /usr/local/bin/start-ollama.sh

RUN chmod +x /usr/local/bin/start-ollama.sh

EXPOSE 11434

ENTRYPOINT ["/usr/local/bin/start-ollama.sh"]
