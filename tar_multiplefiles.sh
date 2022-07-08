#!/bin/bash

# script: tar_multiplefiles.sh
# autor: Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# objetivo: compacta multiplos arquivos de um diretório em multiplos arquivos .tar
# criação: 08 JUL 2022
# ultima atualização: 08 JUL 2022
# atualização: criação do arquivo

# sintaxe
# tar_multiplefiles.sh *.fastq

# solução 1
# for file in `ls $1`; do tar -czvf $file.tar $file ; done

# solução 2
find . -type f -execdir tar -czvf '{}.tar' '{}' \;
