for module in 'Plack' 'DBI' 'Digest::MD5' 'Moose' 'JSON::RPC::Dispatcher' \
    'Try::Tiny' 'TAP::Harness' 'Test::More' \
    'Text::Unidecode' 'Data::UUID' 'DBIx::Sequence'
do
    cpanm --notest $module
done