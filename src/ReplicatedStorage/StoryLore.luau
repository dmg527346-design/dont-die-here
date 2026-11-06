-- Story of Don't Die Here (owner 2026-10-29): data only. The crew are a small alien team; the monsters are the people
-- of a little town who owned the cursed things. Notes: one per level (level 13 = note 1 again, so a missed note can be
-- found later); found ones save in ProgressCore StoryNotes and open the monster's file on the lobby board (StoryClient).
-- Every word is plain English a first grader can read (owner 2026-10-29): short sentences, easy words.
-- Content rules: no blood, no bodies, no red; owners are changed people, never dead ones.
local M={}

M.Land={
 title='THE TOWN',
 text='Long ago, a green star fell on a little town. Its glowing dust got into toys and things in the houses. Each thing gave its owner what they wanted most. Then it gave too much. The people changed. They are still there.',
 crew='You are a small alien team. The green star was a piece of your home. Take the cursed things back to your van. Do not get caught.',
}

-- Monsters on the lobby board, in board order. image = the camera photo. kind = CreatureRoamServer template kind.
M.Subjects={
 {id='Watchman',name='THE WATCHMAN',monster='Lantern Watcher',kind='Lantern',image='rbxassetid://131770432662043',
  owner='Otis, the night guard',
  text='Otis kept the big house safe at night. He put a glowing rock in his lantern so it would never go dark. Now the lantern is his head. He still walks the halls. He still checks every closet.',
  tip='He can see you hide. Do not hide where he saw you go.'},
 {id='Collar',name='THE COLLAR',monster='Collar Crawler',kind='Crawler',image='rbxassetid://131200152774602',
  owner='Mr. Pet, the dog groomer',
  text='Mr. Pet was very lonely. He tried on a shiny dog collar for fun. It never came off. Now he crawls on the floor and sniffs for a new best friend.',
  tip='He listens for you. Walk, do not run.'},
 {id='Weeper',name='THE WEEPER',monster='Tear Wraith',kind='Wraith',image='rbxassetid://127082211514194',
  owner='Miss Dolly, the sewing lady',
  text='Miss Dolly cried all the time. She kept her tears in a magic hanky. The hanky kept every tear. Now she is made of tears. If you see her, she runs at you. Then she runs away.',
  tip='She hits once, then leaves. Get out of her way.'},
 {id='Projectionist',name='THE MOVIE MAN',monster='Neon Tripod',kind='Neon',image='rbxassetid://131169559271014',
  owner='Vince, who showed movies',
  text='Vince showed movies at night. He put a glowing rock in his movie light. The movie never stopped. Now his eyes are lights. He shines them down the halls.',
  tip='Crouch under his light. Do not stand in it.'},
 {id='Knitter',name='THE KNITTER',monster='Lonely Mittens',kind='Mittens',image='rbxassetid://85184620382919',
  owner='Granny Wool',
  text='Granny made mittens for every kid in town, so no one was alone. When the town was empty, she turned into the biggest mitten of all. She looks for kids who walk alone.',
  tip='Stay with your team. She can not see a group.'},
 {id='Ballerina',name='THE DANCER',monster='Wind-Up Dancer',kind='Dancer',image='rbxassetid://94978298305888',
  owner='Clara, the dancer',
  text='Clara wound up a music box so she could dance forever. Now she can not stop. When the music stops, she looks for anyone who moves.',
  tip='When the music stops, stand still.'},
 {id='YoyoKid',name='THE YO-YO KID',monster='Yo-Yo Kid',kind='Yoyo',image='rbxassetid://121307968004382',
  owner='Toby, age 11',
  text='Toby moved away and missed home every day. His yo-yo always came back. He wished he would come back too. He did. Now his head is a big yo-yo.',
  tip='He wants his toys back. Keep moving.'},
}
M.SubjectById={};for i,s in M.Subjects do s.index=i;M.SubjectById[s.id]=s end

-- One note per level. subject = the monster file it opens (nil = story only).
M.Notes={
 {id='N01',title='HELLO, TEAM',from='Your ship',subject=nil,
  text='Hello, team. Welcome to Earth. A piece of our home fell on this town. It is hiding in toys and things. Bring them to the van. The people here are not normal. Do not let them catch you.'},
 {id='N02',title='GUARD BOOK',from='Otis, the night guard',subject='Watchman',
  text='Night 1000. All quiet. Nothing gets out. I checked every closet two times. My lantern feels heavy. That is OK. Nothing gets out.'},
 {id='N03',title='LOST DOG SIGN',from='Taped to a door',subject='Collar',
  text='LOST: my best friend. He will come to any name. If you find him, let him sniff you. He just wants you to stay. Forever. From Mr. Pet.'},
 {id='N04',title='DIARY',from='Miss Dolly',subject='Weeper',
  text='I cried at breakfast. I cried at the shop. My hanky is so heavy now. It hums. If anyone sees me cry, I will run at them until they stop looking.'},
 {id='N05',title='MOVIE TICKET',from='The movie place',subject='Projectionist',
  text='One ticket. The movie: THE BRIGHTEST LIGHT. It plays every night, forever. Stay in your seat. If you stand up, you have to leave. For good.'},
 {id='N06',title='MITTEN PLAN',from='Granny Wool',subject='Knitter',
  text='Make one big mitten. Big enough for a whole granny. Knit until no one is lonely. If a kid walks alone, hold their hand. Never let go.'},
 {id='N07',title='DANCE SIGN',from='The dance hall',subject='Ballerina',
  text='Every night: CLARA DANCES AND NEVER STOPS. If you come late, stand very still when the music stops. Clara sees anyone who moves.'},
 {id='N08',title='POSTCARD',from='Toby',subject='YoyoKid',
  text='Dear home town, my new town is boring. I miss you every day. My yo-yo always comes back. I wished I would come back too. See you soon! Love, Toby. P.S. Do not touch my stuff.'},
 {id='N09',title='SCIENCE NOTE',from='Your ship',subject=nil,
  text='The green star was not a rock. It was a piece of our home. It makes wishes come true. On Earth it does too much. That is why the cursed things pull at you.'},
 {id='N10',title='TEAM 7',from='An old helmet',subject=nil,
  text='This is Team 7. Our van is full. But the lights in the hall keep following us. We went back in for one more thing. Only our empty suits came out.'},
 {id='N11',title='SHIP SAYS',from='Your ship',subject=nil,
  text='Fuel is low. The people get stronger when we take more. Never go alone. Never stay in one room. Never trust a quiet hall. And do not die here.'},
 {id='N12',title='NOTE ON THE VAN SEAT',from='No name',subject=nil,
  text='You think you are taking the pieces home. I did too. Who do you think gave the people their cursed things? Keep filling the van. I will wait for you at the end of the road. From The Collector.'},
}
M.NoteById={};for i,n in M.Notes do n.index=i;M.NoteById[n.id]=n end

function M.NoteForLevel(level)
 local n=#M.Notes;local i=((math.max(1,math.floor(tonumber(level)or 1))-1)%n)+1
 return M.Notes[i]
end
-- A monster's file is open once a note that names it is found.
function M.SubjectUnlocked(found,subjectId)
 for _,n in M.Notes do if n.subject==subjectId and found[n.id]~=nil then return true end end
 return false
end

return M
