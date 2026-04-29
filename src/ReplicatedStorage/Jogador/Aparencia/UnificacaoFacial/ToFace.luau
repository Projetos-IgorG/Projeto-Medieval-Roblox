--[[
	Script: ToFace.luau
	Caminho: src/ReplicatedStorage/Jogador/Aparencia/UnificacaoFacial
	Responsabilidade: Mapeia ids de dynamic heads para faces classicas e meshes de cabeca (Facial Unification v1.4).
	Uso: ModuleScript; lido por UnificacaoFacial ao converter heads animados em equivalentes 2D.
	Nao faz: Nao cria instancias nem altera personagens; apenas retorna a tabela de mapeamento.
	Funcoes principais: nenhuma; retorna tabela Head -> {Face, Head}
]]
return {
	-- FACES (01/28/2026)
	[115499438051492] = {Face = 25321961; Head = 0}; -- Friendly Grin;
	[15554865353] = {Face = 20722130; Head = 0}; -- Shiny Teeth;
	[13682084865] = {Face = 6531983163; Head = 0}; -- Award-Winning Smile;
	[15093427659] = {Face = 14861743; Head = 0}; -- :P;
	[15381533776] = {Face = 26260927; Head = 0}; -- Scarecrow;
	[16042049101] = {Face = 236399287; Head = 0}; -- Happy Wink;
	[16041877976] = {Face = 7317793; Head = 0}; -- Good Intentioned;
	[15548514852] = {Face = 30394850; Head = 0}; -- Awesome Face;
	[15555890394] = {Face = 7074729; Head = 0}; -- Glee;
	[15938951781] = {Face = 7699174; Head = 86498113}; -- Silly Fun;
	[14484001930] = {Face = 8329679; Head = 746767604}; -- Stitchface;
	[14193662834] = {Face = 391496223; Head = 0}; -- Big Sad Eyes;
	[13822758815] = {Face = 8329686; Head = 0}; -- Sinister;
	[11308682721] = {Face = 25166274; Head = 86498113}; -- Squiggle Mouth;
	[11308884165] = {Face = 20418658; Head = 0}; -- Err...;
	[11244608373] = {Face = 12145366; Head = 86498113}; -- Freckles;
	[12936972483] = {Face = 7987180607; Head = 86498113}; -- Big Grin - Tai Verdes;
	[13820838786] = {Face = 173789324; Head = 0}; -- Not Sure If...;
	[13822633229] = {Face = 150182466; Head = 0}; -- Huh?;
	[12936650534] = {Face = 7893455671; Head = 86498113}; -- Cat Eye - Zara Larsson;
	[11159990982] = {Face = 4018627046; Head = 86498113}; -- Classic Female Face;
	[13821263793] = {Face = 406001167; Head = 746767604}; -- ROAR!!!;
	[14478101144] = {Face = 7317765; Head = 0}; -- Slick Fang aka Slickfang;
	[13692956122] = {Face = 209994929; Head = 0}; -- Suspicious;
	[13692793711] = {Face = 5917459717; Head = 86498113}; -- Smil Nas X - Lil Nas X (LNX);
	[11180212350] = {Face = 4018617474; Head = 0}; -- Classic Male Face;
	[14478328247] = {Face = 7893460486; Head = 86498113}; -- Glittering Eye - Zara Larsson;
	[14193299178] = {Face = 7657646351; Head = 86498113}; -- Butterfly Wink - Lil Nas X (LNX);
	[14525047012] = {Face = 7506141; Head = 0}; -- It's Go Time!;
	[13821330310] = {Face = 15637848; Head = 0}; -- -_-;
	[11163789916] = {Face = 616380929; Head = 0}; -- The Winning Smile;
	[11236434712] = {Face = 7074764; Head = 0}; -- Chill;
	[14193774321] = {Face = 14193774321; Head = 0}; -- :-/;
	[14205261998] = {Face = 49045351; Head = 0}; -- Monster Face;
	[13693003885] = {Face = 20298988; Head = 0}; -- Puck;
	[13692947484] = {Face = 8560971; Head = 0}; -- Stare;
	[12937204578] = {Face = 226217449; Head = 86498113}; -- Laughing Fun;
	[14483837205] = {Face = 20337343; Head = 0}; -- Disbelief;
	[14205289572] = {Face = 7317773; Head = 0}; -- :-o (No Nose);
	[13823337209] = {Face = 15324577; Head = 0}; -- >_<;
	[13682108684] = {Face = 29532363; Head = 0}; -- Vampire;
	[13820744684] = {Face = 416846300; Head = 86498113}; -- Anime Surprise;
	[14193509240] = {Face = 12467159; Head = 0}; -- Ghostface;
	[14719537379] = {Face = 15432080; Head = 0}; -- :3;
	[12946305202] = {Face = 162068415; Head = 0}; -- YAAAWWN;
	[11822739674] = {Face = 209994875; Head = 86498113}; -- Stay Positive aka Smiling Girl;
	[12954264879] = {Face = 209995366; Head = 0}; -- Joyful Smile;
	[13675180453] = {Face = 2222771916; Head = 0}; -- Hold It In;
	[12992668217] = {Face = 22877700; Head = 86498113}; -- Whistle;
	[13821486499] = {Face = 28999228; Head = 0}; -- Joyous Surprise;
	[13682077493] = {Face = 10907551; Head = 0}; -- Dizzy Face;
	[13692975981] = {Face = 616381207; Head = 0}; -- Friendly Smile;
	[13702692127] = {Face = 32058239; Head = 0}; -- So Funny;
	[14193608834] = {Face = 14030577; Head = 0}; -- I Hate Noobs;
	[12939347925] = {Face = 26424808; Head = 0}; -- Know-It-All Grin;
	[13702615195] = {Face = 19398554; Head = 0}; -- Grr!;
	[13691995281] = {Face = 21635565; Head = 0}; -- Heeeeeey...;
	[14193899807] = {Face = 15366173; Head = 0}; -- ^_^;
	[14474232253] = {Face = 7074864; Head = 0}; -- Winky;
	[13692942131] = {Face = 15470849; Head = 86498113}; -- Hut Hut Hike!;
	[14532846222] = {Face = 599913343; Head = 0}; -- Skeptic; // I have used Jacob: The Storm Breaker Face, because it's a HD rendition!
	[14193559599] = {Face = 14516578; Head = 86498113}; -- Sniffles;
	[13692999952] = {Face = 10907549; Head = 0}; -- Finn McCool;
	[12937095639] = {Face = 18151826; Head = 0}; -- :];
	[13823254076] = {Face = 32723404; Head = 0}; -- I <3 New Site Theme;
	[14525311372] = {Face = 15885121; Head = 86498113}; -- Cutiemouse;
	[13675083217] = {Face = 7074893; Head = 0}; -- Drool;
	[13682064263] = {Face = 406000730; Head = 0}; -- Happy :D;
	[12945410659] = {Face = 30394484; Head = 0}; -- Braces;
	[10725626210] = {Face = 86487766; Head = 86498113}; -- Woman Face;
	[10725826963] = {Face = 86487700; Head = 86498048}; -- Man Face;
	[11308945948] = {Face = 7074786; Head = 0}; -- Check It;
	[15381635341] = {Face = 7075502; Head = 0}; -- Lazy Eye;
	[15381595196] = {Face = 23932048; Head = 0}; -- Awkward....;
	
	-- BUNDLE FACES (01/28/2026)
	[12930215322] = {Face = 301826803; Head = 0}; -- Lin's Face; // Why is it the only Xbox face to get it tho?
	[11822635053] = {Face = 4637244809; Head = 4637245706;}; -- Dennis aka Classic Male v2 Face;
	[15093144795] = {Face = 4637291815; Head = 4637163809;}; -- Kenneth aka NeoClassic Male v2 Face;
	[12945228337] = {Face = 4637266368; Head = 4637266996;}; -- Lindsey aka Classic Female v2 Face;
	[13253943097] = {Face = 4637166178; Head = 4637441617;}; -- Cindy aka NeoClassic Female v2 Face;
	[18714367431] = {Face = 86487700; Head = 86498048}; -- Legendary Sky Champion Head (Man Face);
	
	-- DEFAULT FACES, ID = 0
	[10638267973] = {Face = 0; Head = 0}; -- Stevie Standard;
	[10687288296] = {Face = 0; Head = 86498048}; -- Dylan Default;
	[10723855306] = {Face = 0; Head = 86498113}; -- Devon Default;
}