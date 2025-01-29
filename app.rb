require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

db = SQLite3::Database.new "db/pokemon.db"
db.results_as_hash = true 

get('/') do

  slim(:index)
end

get('/pokemons') do

  @pokemons = db.execute("SELECT p.id, p.name, t1.name AS type1, t2.name AS type2, p.hp, p.attack, p.defense, p.sp_attack, p.sp_defense, p.speed FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id")
  slim(:pokemons)
end

get('/pokemons/:name') do
  name = params[:name]
  @pokemon = db.execute("SELECT * FROM Pokemons WHERE name = ?", name)
  slim(:pokemon)

end

get '/search' do
  query = params[:query]
  return [].to_json if query.nil? || query.strip.empty?

  # Sök i databasen
  results = db.execute(
    "SELECT name, type1, type2 FROM Pokemons WHERE name LIKE ? LIMIT 10",
    "%#{query}%"
  )

  # Returnera resultaten som JSON
  content_type :json
  results.to_json
end


