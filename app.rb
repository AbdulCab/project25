require 'sinatra'
require 'sinatra\reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

get('/') do
  slim("index")
end

get('/pokemons') do
  db = SQLite3::Database.new("db/pokemon.db")
  db.results_as_hash = true
  result = db.execute("SELECT * FROM Pokemons")
  p result
  
end

