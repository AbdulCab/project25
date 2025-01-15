require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'poke-api-v2'

db = SQLite3::Database.new('db/pokemon.db')
db.results_as_hash = true

#
def fetch_pokemon_by_name(db, name)
  # Kör SQL-frågan
  result = db.execute("SELECT * FROM pokemons WHERE name = ?", [name])

  if result.empty?
    puts "Ingen Pokémon hittades med namnet '#{name}'."
  else
    puts "Hittad Pokémon: "
    result.each do |row|
      puts "ID: #{row['id']}, Namn: #{row['name']}, Typ1: #{row['type1']}, Typ2: #{row['type2']}"
    end
  end
end

# Testa att hämta en Pokémon (t.ex. Pikachu)
fetch_pokemon_by_name(db, 'pikachu')