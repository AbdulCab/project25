require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'

db = SQLite3::Database.new "db/pokemon.db"
db.results_as_hash = true 

get('/') do

  slim(:index)
end

get('/pokedex') do

  @pokemons = db.execute("SELECT p.id, p.name, t1.name AS type1, t2.name AS type2, p.hp, p.attack, p.defense, p.sp_attack, p.sp_defense, p.speed FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id")
  slim(:pokedex)
end

get('/pokedex/:name') do
  name = params[:name]
  @pokemon = db.execute("SELECT * FROM Pokemons WHERE name = ?", name)
  slim(:pokemon)

end

get '/search' do
  slim :search
end

# Route to return filtered Pokémon in JSON format
get '/search_pokemon' do
  query = params[:q].to_s.downcase.strip

  pokemons = db.execute <<-SQL, ["%#{query}%"]
    SELECT "Pokemons".id, "Pokemons".name, 
           t1.name AS type1, 
           t2.name AS type2 
    FROM "Pokemons"
    LEFT JOIN types t1 ON "Pokemons".type1 = t1.id
    LEFT JOIN types t2 ON "Pokemons".type2 = t2.id
    WHERE LOWER("Pokemons".name) LIKE ?
  SQL

  # Generate dynamic image URL based on Pokémon ID

  pokemon.each do |pokemon|
    pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{pokemon['id']}.png"
    pokemon["types"] = pokemon["type2"] ? "#{pokemon['type1']} / #{pokemon['type2']}" : pokemon["type1"]
  end
  
  content_type :json
  pokemons.to_json
end


