function searchPokemon() {
    const query = document.getElementById("search-input").value;
  
    if (query.trim() === "") {
      document.getElementById("search-results").innerHTML = ""; // Rensa resultaten
      return;
    }
  
    fetch(`/search?query=${encodeURIComponent(query)}`)
      .then((response) => response.json())
      .then((data) => {
        const resultsContainer = document.getElementById("search-results");
        resultsContainer.innerHTML = ""; // Rensa gamla resultat
  
        if (data.length === 0) {
          resultsContainer.innerHTML = "<p>Inga resultat hittades.</p>";
          return;
        }
  
        data.forEach((pokemon) => {
          const result = document.createElement("div");
          result.className = "search-result";
          result.innerHTML = `
            <p><strong>${pokemon.name}</strong> (${pokemon.type1}${pokemon.type2 ? ` / ${pokemon.type2}` : ""})</p>
          `;
          resultsContainer.appendChild(result);
        });
      })
      .catch((error) => console.error("Error:", error));
  }
  