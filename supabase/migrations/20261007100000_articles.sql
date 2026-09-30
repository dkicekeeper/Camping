-- Статьи и советы (M5c): редакционные статьи на трёх языках, читают все (и гости).
--
-- Текст — подмножество Markdown, которое показывает приложение: заголовки ## и ###, абзацы,
-- списки «- » и «1. », выноска «> », **жирный**, *курсив*, ссылки. Исходники статей и проверка
-- разметки — supabase/data/articles (build_sql.py). Правка опубликованной статьи — новой миграцией
-- или в Supabase Studio; приложение подхватит изменения в течение часа.

create type public.article_category as enum (
  'tackle', 'knots', 'technique', 'cooking', 'safety', 'rules_ethics', 'places_seasons'
);

create table public.articles (
  id            text primary key check (id ~ '^[a-z0-9_]{2,60}$'),
  category      public.article_category not null,
  title_ru      text not null check (char_length(btrim(title_ru)) between 1 and 120),
  title_kk      text not null check (char_length(title_kk) <= 120),
  title_en      text not null check (char_length(title_en) <= 120),
  summary_ru    text not null check (char_length(btrim(summary_ru)) between 1 and 300),
  summary_kk    text not null check (char_length(summary_kk) <= 300),
  summary_en    text not null check (char_length(summary_en) <= 300),
  -- Пустой перевод — приложение покажет русский текст.
  body_ru       text not null check (char_length(btrim(body_ru)) between 1 and 40000),
  body_kk       text not null check (char_length(body_kk) <= 40000),
  body_en       text not null check (char_length(body_en) <= 40000),
  published_on  date not null default current_date,
  sort_order    integer not null default 100,
  -- Черновик (false) не виден в приложении.
  is_published  boolean not null default true,
  updated_at    timestamptz not null default now()
);

create function private.articles_touch() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger articles_touch before update on public.articles
  for each row execute function private.articles_touch();

alter table public.articles enable row level security;

revoke all on table public.articles from anon, authenticated;
grant select on table public.articles to anon, authenticated;

create policy "articles: читать опубликованные" on public.articles
  for select to anon, authenticated using (is_published);

-- Первые статьи. Казахский и английский — черновик на вычитку.
insert into public.articles
  (id, category, sort_order, published_on,
   title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en, body_ru, body_kk, body_en)
values
  ('ice_safety',
   'safety',
   10,
   date '2026-09-30',
   $md$Безопасность на льду$md$,
   $md$Мұздағы қауіпсіздік$md$,
   $md$Ice safety$md$,
   $md$Какой лёд держит, что взять с собой и что делать, если провалились.$md$,
   $md$Қандай мұз көтереді, өзіңізбен не алу керек және мұз ойылып кетсе не істеу керек.$md$,
   $md$Which ice holds, what to bring and what to do if you fall through.$md$,
   $md$Зимняя рыбалка начинается с проверки льда. Больше всего несчастных случаев — в начале и в конце сезона, когда лёд кажется крепким, но ещё или уже не держит.

## Какой лёд держит

- **Тоньше 7 см** — не выходите.
- **От 7 см** — выдержит одного человека.
- **От 12–15 см** — можно идти группой, на расстоянии 5–6 метров друг от друга.

Прозрачный лёд с синеватым или зеленоватым оттенком — самый прочный. Белый, мутный, пористый лёд примерно вдвое слабее. Серый, жёлтый и тёмный лёд, лёд после оттепели и под слоем снега — опасен.

## Где лёд тоньше

- у берега — в начале и в конце сезона;
- в устьях рек и ручьёв, над течением, у камыша, коряг и опор мостов;
- над родниками и на месте старых лунок;
- под снегом: он укрывает лёд и не даёт ему нарасти.

## Что взять

- **Пешню.** Простукивайте лёд перед собой каждые несколько шагов. Если он пробивается с одного-двух ударов — возвращайтесь по своим следам.
- **Спасалки** на шее и **верёвку** 15–20 м с петлёй на конце.
- Заряженный телефон в непромокаемом пакете.
- Сухую сменную одежду — в рюкзаке или в машине.

Скажите близким, куда идёте и когда вернётесь. Не выходите на лёд в одиночку и в темноте.

## Если провалились

1. Не паникуйте и не сбрасывайте одежду: пока она не промокла, она держит на воде.
2. Широко раскиньте руки по кромке льда.
3. Развернитесь туда, откуда пришли, — там лёд уже выдержал.
4. Работая ногами, вытолкните тело на лёд, помогайте себе спасалками.
5. Выбравшись, не вставайте: откатитесь или отползите по своим следам.
6. Как можно быстрее переоденьтесь в сухое и согрейтесь. Звоните **112**.

## Если провалился другой

Не бегите к нему. Подползите на 3–4 метра и подайте верёвку, шарф, ремень или палку. Вызовите помощь — **112**.

> Сведения справочные. Следите за предупреждениями МЧС о выходе на лёд.$md$,
   $md$Қысқы балық аулау мұзды тексеруден басталады. Жазатайым оқиғалардың көбі маусымның басы мен соңында болады: мұз берік көрінгенімен, әлі немесе енді көтермейді.

## Қандай мұз көтереді

- **7 см-ден жұқа** — шықпаңыз.
- **7 см-ден бастап** — бір адамды көтереді.
- **12–15 см-ден бастап** — бір-бірінен 5–6 метр қашықтықта топпен жүруге болады.

Көгілдір немесе жасылдау реңкі бар мөлдір мұз ең берік. Ақ, күңгірт, кеуекті мұз шамамен екі есе әлсіз. Сұр, сары және қара мұз, жылымықтан кейінгі және қар астындағы мұз қауіпті.

## Мұз қай жерде жұқа

- жағада — маусымның басы мен соңында;
- өзендер мен бұлақтардың сағасында, ағыс үстінде, қамыс, қу ағаш және көпір тіректерінің жанында;
- бұлақ көздерінің үстінде және ескі ойықтардың орнында;
- қар астында: қар мұзды жауып, оның қалыңдауына кедергі жасайды.

## Не алу керек

- **Сүймен.** Әр бірнеше қадам сайын алдыңыздағы мұзды соғып тексеріңіз. Мұз бір-екі соққыдан тесілсе — өз ізіңізбен кері қайтыңыз.
- Мойынға **құтқарғыштар** және ұшында ілмегі бар 15–20 м **арқан**.
- Су өтпейтін қалтадағы зарядталған телефон.
- Құрғақ ауыстыратын киім — рюкзакта немесе көлікте.

Жақындарыңызға қайда баратыныңызды және қашан оралатыныңызды айтыңыз. Мұзға жалғыз және қараңғыда шықпаңыз.

## Мұз ойылып кетсе

1. Сасқалақтамаңыз және киіміңізді шешпеңіз: суға толық малынбайынша ол суда ұстап тұрады.
2. Қолдарыңызды мұздың шетіне кең жайыңыз.
3. Келген жағыңызға бұрылыңыз — ондағы мұз сізді көтерген.
4. Аяқпен жұмыс істеп, денеңізді мұзға итеріп шығарыңыз, құтқарғыштармен көмектесіңіз.
5. Шыққаннан кейін тұрмаңыз: өз ізіңізбен домалап немесе еңбектеп кетіңіз.
6. Мүмкіндігінше тезірек құрғақ киім киіп, жылыныңыз. **112**-ге қоңырау шалыңыз.

## Басқа адам ойылып кетсе

Оған қарай жүгірмеңіз. 3–4 метрге дейін еңбектеп жақындап, арқан, шарф, белбеу немесе таяқ ұсыныңыз. Көмек шақырыңыз — **112**.

> Мәліметтер анықтамалық сипатта. ТЖМ-нің мұзға шығу туралы ескертулерін қадағалаңыз.$md$,
   $md$Ice fishing starts with checking the ice. Most accidents happen early and late in the season, when the ice looks solid but is not yet, or no longer, strong enough.

## Which ice holds

- **Under 7 cm** — stay off.
- **7 cm or more** — holds one person.
- **12–15 cm or more** — a group can walk, 5–6 metres apart.

Clear ice with a bluish or greenish tint is the strongest. White, cloudy, porous ice is about half as strong. Grey, yellow or dark ice, ice after a thaw and ice under snow are dangerous.

## Where the ice is thinner

- near the shore early and late in the season;
- at river and stream mouths, over currents, near reeds, snags and bridge piers;
- over springs and old holes;
- under snow: it insulates the ice and keeps it from growing.

## What to bring

- **An ice chisel.** Tap the ice ahead of you every few steps. If it breaks after one or two blows, go back the way you came.
- **Ice picks** around your neck and a **rope** of 15–20 m with a loop at the end.
- A charged phone in a waterproof bag.
- Dry spare clothes in your backpack or car.

Tell someone where you are going and when you will be back. Do not go on the ice alone or in the dark.

## If you fall through

1. Stay calm and keep your clothes on: until they are soaked, they help you float.
2. Spread your arms wide on the edge of the ice.
3. Turn towards where you came from — that ice has already held you.
4. Kick with your legs to push your body onto the ice, helping yourself with the ice picks.
5. Once out, do not stand up: roll or crawl back along your tracks.
6. Change into dry clothes and warm up as soon as possible. Call **112**.

## If someone else falls through

Do not run to them. Crawl to within 3–4 metres and pass them a rope, scarf, belt or stick. Call for help — **112**.

> For reference only. Follow the Emergency Ministry's warnings about going on the ice.$md$),
  ('summer_safety',
   'safety',
   20,
   date '2026-09-30',
   $md$Жара, клещи и змеи$md$,
   $md$Ыстық, кене және жылан$md$,
   $md$Heat, ticks and snakes$md$,
   $md$Три летние опасности у воды в Алматинской области и как помочь себе и другим.$md$,
   $md$Алматы облысында су жағасындағы жазғы үш қауіп және өзіңізге әрі басқаларға қалай көмектесу керек.$md$,
   $md$Three summer dangers by the water in Almaty region and how to help yourself and others.$md$,
   $md$Летом у воды в Алматинской области три главные опасности: жара, клещи и змеи. Все три проще предупредить, чем лечить.

## Жара

На Капшагае и Иле днём бывает за 40 °C, а тени почти нет.

- Пейте воду часто и понемногу, не дожидаясь жажды. Берите не меньше 3 литров на человека в день.
- Головной убор, светлая одежда с длинным рукавом, солнцезащитный крем.
- В самые жаркие часы, примерно с 12 до 16, отдыхайте в тени. Тяжёлую работу — утром и вечером.
- Алкоголь в жару усиливает обезвоживание.

**Тепловой удар:** слабость, головная боль, тошнота, горячая сухая кожа, спутанность сознания. Уведите человека в тень, снимите лишнюю одежду, охлаждайте мокрой тканью и обмахиванием. Если он в сознании — давайте пить маленькими глотками. Если сознание спутано — звоните **112**.

## Клещи

Алматинская область — зона клещевого энцефалита. Больше всего клещей весной и в начале лета — в траве, кустах и в предгорьях.

- Прививку от клещевого энцефалита делают заранее — узнайте в поликлинике.
- В траве и кустах — светлая одежда, брюки заправлены в носки, средство от клещей на одежде.
- Осматривайте себя и друг друга каждые 2–3 часа и вечером.

**Если клещ присосался:** захватите его пинцетом или специальной петлёй как можно ближе к коже и выкрутите, не раздавливая. Место укуса обработайте антисептиком. Положите клеща в закрытую баночку и обратитесь к врачу — клеща можно проверить в лаборатории.

## Змеи

В регионе встречаются ядовитые змеи — степная гадюка и щитомордник. Змеи не нападают первыми: кусают, когда на них наступают или пытаются взять в руки.

- Смотрите под ноги. В высокой траве и среди камней идите не тихо — постукивайте палкой.
- Закрытая обувь и плотные брюки.
- Не поднимайте камни и коряги голыми руками, проверяйте обувь и спальник перед тем, как надеть или лечь.

**При укусе:** уложите пострадавшего и успокойте его. Снимите кольца, часы и браслеты с укушенной руки или ноги и не давайте ею двигать — наложите шину из подручных средств. Давайте пить. Срочно к врачу — **112**.

**Нельзя:** надрезать и прижигать место укуса, отсасывать яд, накладывать жгут, давать алкоголь.

> Статья не заменяет врача. Если человеку становится хуже — звоните 112.$md$,
   $md$Жазда Алматы облысында су жағасындағы үш басты қауіп — ыстық, кене және жылан. Үшеуінің де алдын алу емдеуден оңай.

## Ыстық

Қапшағай мен Іле бойында күндіз 40 °C-тан асады, ал көлеңке жоқтың қасы.

- Шөлдегенді күтпей, суды жиі әрі аздап ішіңіз. Бір адамға күніне кемінде 3 литр су алыңыз.
- Бас киім, ұзын жеңді ашық түсті киім, күннен қорғайтын крем.
- Ең ыстық сағаттарда, шамамен 12-ден 16-ға дейін, көлеңкеде демалыңыз. Ауыр жұмысты таңертең және кешке істеңіз.
- Ыстықта алкоголь сусыздануды күшейтеді.

**Күн өту:** әлсіздік, бас ауыруы, жүрек айнуы, ыстық құрғақ тері, сананың шатасуы. Адамды көлеңкеге апарып, артық киімін шешіңіз, дымқыл матамен және желпіп салқындатыңыз. Есі дұрыс болса, аз-аздан ішкізіңіз. Санасы шатасса — **112**-ге қоңырау шалыңыз.

## Кене

Алматы облысы — кене энцефалиті тараған аймақ. Кене көктемде және жаздың басында көп болады — шөпте, бұталарда және тау бөктерінде.

- Кене энцефалитіне қарсы екпе алдын ала салынады — емханадан біліңіз.
- Шөп пен бұта арасында — ашық түсті киім, шалбарды шұлыққа салыңыз, киімге кенеге қарсы құрал жағыңыз.
- Әр 2–3 сағат сайын және кешке өзіңізді және бір-біріңізді тексеріңіз.

**Кене жабысып қалса:** оны пинцетпен немесе арнайы ілмекпен теріге барынша жақын ұстап, жаншымай бұрап шығарыңыз. Шаққан жерді антисептикпен өңдеңіз. Кенені жабық ыдысқа салып, дәрігерге барыңыз — кенені зертханада тексеруге болады.

## Жылан

Өңірде улы жыландар — дала сұр жыланы мен қалқантұмсық кездеседі. Жылан бірінші шабуыл жасамайды: оны басып кеткенде немесе қолға алғанда шағады.

- Аяқ астына қараңыз. Биік шөпте және тас арасында дыбыс шығарып — таяқпен тықылдатып жүріңіз.
- Жабық аяқ киім және қалың шалбар киіңіз.
- Тас пен қу ағашты жалаң қолмен көтермеңіз, аяқ киім мен ұйықтау қабын кияр не жатар алдында тексеріңіз.

**Жылан шақса:** зардап шегушіні жатқызып, тыныштандырыңыз. Шағылған қол немесе аяқтан сақина, сағат, білезікті шешіп, оны қимылдатпаңыз — қолда бар заттан шина салыңыз. Су беріңіз. Шұғыл түрде дәрігерге — **112**.

**Болмайды:** шаққан жерді тіліп не күйдіруге, уды сорып алуға, бұрау салуға, алкоголь беруге.

> Мақала дәрігердің орнын баспайды. Адамның жағдайы нашарласа — 112-ге қоңырау шалыңыз.$md$,
   $md$In summer, the three main dangers by the water in Almaty region are heat, ticks and snakes. All three are easier to prevent than to treat.

## Heat

Days on Kapshagay and the Ile can go above 40 °C, with almost no shade.

- Drink little and often, before you feel thirsty. Bring at least 3 litres per person per day.
- Wear a hat, light long-sleeved clothes and sunscreen.
- During the hottest hours, roughly 12:00 to 16:00, rest in the shade. Do hard work in the morning and evening.
- Alcohol makes dehydration worse.

**Heat stroke:** weakness, headache, nausea, hot dry skin, confusion. Move the person into the shade, remove extra clothing, cool them with wet cloth and fanning. If they are conscious, give small sips of water. If they are confused, call **112**.

## Ticks

Almaty region is a tick-borne encephalitis area. Ticks are most active in spring and early summer, in grass, bushes and the foothills.

- The tick-borne encephalitis vaccine is given in advance — ask at your clinic.
- In grass and bushes wear light clothes, tuck your trousers into your socks and use tick repellent on your clothes.
- Check yourself and each other every 2–3 hours and in the evening.

**If a tick has attached:** grip it with tweezers or a tick loop as close to the skin as possible and twist it out without crushing it. Disinfect the bite. Put the tick in a closed jar and see a doctor — the tick can be tested in a lab.

## Snakes

The region has venomous snakes — the steppe viper and the Central Asian pit viper. Snakes do not attack first: they bite when stepped on or picked up.

- Watch where you step. In tall grass and among rocks, make noise by tapping a stick.
- Wear closed shoes and thick trousers.
- Do not lift rocks and snags with bare hands; check your shoes and sleeping bag before putting them on or lying down.

**If bitten:** lay the person down and keep them calm. Remove rings, watches and bracelets from the bitten limb and keep it still with a splint made from whatever is at hand. Give them water. Get to a doctor urgently — **112**.

**Do not** cut or burn the bite, suck out the venom, apply a tourniquet or give alcohol.

> This article does not replace a doctor. If the person gets worse, call 112.$md$),
  ('fish_release',
   'rules_ethics',
   30,
   date '2026-09-30',
   $md$Как отпустить рыбу, чтобы она выжила$md$,
   $md$Балық тірі қалатындай етіп қалай жіберу керек$md$,
   $md$How to release a fish so it survives$md$,
   $md$Рыбу меньше промысловой меры и пойманную в запрет нужно отпустить. Вот как сделать это правильно.$md$,
   $md$Кәсіптік өлшемнен кіші және тыйым кезінде ұсталған балықты жіберу керек. Мұны қалай дұрыс істеу керегі осында.$md$,
   $md$Fish below the minimum size or caught during a ban must be released. Here is how to do it right.$md$,
   $md$Рыбу нужно отпустить, если она меньше промысловой меры, если поймана в нерестовый запрет или если вид ловить запрещено. И просто — если вы не собираетесь её есть. Правильно отпущенная рыба почти всегда выживает.

## Ещё до поимки

- Ставьте крючки без бородки или прижмите бородку плоскогубцами. Рыбу проще отпустить, а сходов почти не прибавится.
- Не затягивайте вываживание: уставшая рыба хуже восстанавливается.
- Возьмите экстрактор, кусачки и рулетку. Промысловая мера для водоёма — в Dalada, в разделе «Правила и запреты».

## Когда рыба у берега

1. По возможности снимайте рыбу с крючка прямо в воде.
2. Если нужно взять в руки — сначала намочите их. Сухие руки и тряпка снимают слизь, которая защищает рыбу от болезней.
3. Не сжимайте рыбу и не берите за жабры и глаза. Крупную держите горизонтально, поддерживая под брюхо.
4. Крючок доставайте экстрактором. Если рыба заглотила его глубоко — обрежьте поводок как можно ближе ко рту: это безопаснее, чем вырывать крючок.
5. Фотографируйте и измеряйте быстро: держите рыбу над водой не дольше, чем сами можете не дышать.

## Как отпустить

Опустите рыбу в воду головой против течения и держите, пока она сама не начнёт двигать жабрами и не уйдёт. Не бросайте рыбу в воду с высоты.

## В приложении

Если длина улова меньше промысловой меры в этом месте, форма улова предупредит, что такую рыбу нужно отпустить. Включите «Отпустил» — это будет видно в отчёте.$md$,
   $md$Балық кәсіптік өлшемнен кіші болса, уылдырық шашу тыйымы кезінде ұсталса немесе бұл түрді аулауға тыйым салынса, оны жіберу керек. Жай ғана жегіңіз келмесе де жіберіңіз. Дұрыс жіберілген балық әрдайым дерлік тірі қалады.

## Балықты ұстамай тұрып

- Сақалы жоқ ілмектерді қолданыңыз немесе сақалын қысқышпен басып тастаңыз. Балықты жіберу оңайырақ, ал жіберіп алу көбеймейді.
- Балықты ұзақ шаршатпаңыз: шаршаған балық нашар қалпына келеді.
- Ілмек суырғыш, тістеуік және рулетка алыңыз. Су айдынының кәсіптік өлшемі Dalada-да, «Ережелер мен тыйымдар» бөлімінде.

## Балық жағаға жеткенде

1. Мүмкін болса, балықты ілмектен тура суда шешіңіз.
2. Қолға алу керек болса — алдымен қолыңызды сулаңыз. Құрғақ қол мен шүберек балықты аурудан қорғайтын шырышты сыдырып кетеді.
3. Балықты қыспаңыз, желбезек пен көзінен ұстамаңыз. Ірі балықты қарнынан демеп, көлденең ұстаңыз.
4. Ілмекті ілмек суырғышпен шығарыңыз. Балық оны терең жұтып қойса — жетекшіні аузына барынша жақын кесіңіз: бұл ілмекті жұлып алудан қауіпсіз.
5. Суретке түсіріп, тез өлшеңіз: балықты судан тыс өзіңіз тыныс алмай тұра алатын уақыттан ұзақ ұстамаңыз.

## Қалай жіберу керек

Балықты басын ағысқа қарсы қаратып суға түсіріп, желбезегін өзі қимылдатып, жүзіп кеткенше ұстап тұрыңыз. Балықты биіктен суға лақтырмаңыз.

## Қосымшада

Аулаған балықтың ұзындығы осы жердегі кәсіптік өлшемнен кіші болса, аулау формасы мұндай балықты жіберу керектігін ескертеді. «Босатып жібердім» дегенді қосыңыз — бұл есепте көрінеді.$md$,
   $md$Release a fish if it is below the minimum size, if it was caught during a spawning ban or if the species is protected. And simply if you are not going to eat it. A fish released properly almost always survives.

## Before you catch it

- Use barbless hooks or flatten the barb with pliers. The fish is easier to release and you will hardly lose more.
- Do not play the fish for too long: a tired fish recovers worse.
- Bring a hook remover, pliers and a tape measure. The minimum sizes for each water are in Dalada under Rules and bans.

## When the fish is at the bank

1. If you can, unhook the fish while it is still in the water.
2. If you need to hold it, wet your hands first. Dry hands and cloths remove the slime that protects the fish from disease.
3. Do not squeeze the fish or hold it by the gills or eyes. Hold a big fish horizontally, supporting its belly.
4. Remove the hook with a hook remover. If the fish has swallowed it deeply, cut the leader as close to the mouth as possible: this is safer than tearing the hook out.
5. Take photos and measure quickly: keep the fish out of the water no longer than you can hold your own breath.

## Letting it go

Hold the fish in the water with its head facing the current until it starts moving its gills and swims away on its own. Do not throw the fish into the water from a height.

## In the app

If the length of a catch is below the minimum size at that place, the catch form will warn you that the fish must be released. Turn on Released — this shows in your report.$md$),
  ('feeder_basics',
   'tackle',
   40,
   date '2026-09-30',
   $md$Фидер для начинающих$md$,
   $md$Бастаушыларға арналған фидер$md$,
   $md$Feeder fishing for beginners$md$,
   $md$Какую снасть собрать, чтобы ловить сазана, карася и леща с берега.$md$,
   $md$Жағадан сазан, мөңке және табан балық аулау үшін қандай құрал жинау керек.$md$,
   $md$Which tackle to put together to catch carp, crucian carp and bream from the bank.$md$,
   $md$Фидер — донная снасть с кормушкой: она доставляет прикормку и насадку в одну точку. На Капшагае, Иле, прудах и платниках вокруг Алматы это самый простой способ поймать сазана, карася и леща с берега.

## Что собрать

- **Удилище** 3,6–3,9 м с тестом до 80–100 г. В комплекте — несколько сменных вершинок разной жёсткости: по их изгибу видно поклёвку.
- **Катушка** размера 3000–4000.
- **Основная леска:** монолеска 0,25–0,28 мм или плетёный шнур 0,12–0,14 мм. К шнуру привяжите шок-лидер — 10–15 м монолески 0,30–0,35 мм: он гасит рывок при дальнем забросе.
- **Кормушки** 40–80 г: на течении Иле — тяжелее, на пруду — легче.
- **Поводки** 30–60 см из лески 0,16–0,20 мм, крючки № 8–12.
- **Подставка** для удилища и **подсачек**.

## Монтаж

Проще всего — скользящая кормушка. Кормушка на карабине свободно ходит по основной леске, ниже — бусина-стопор, вертлюжок и поводок с крючком. Рыба берёт насадку и почти не чувствует веса кормушки.

## Насадка и прикормка

- **Сазан и карась:** кукуруза, горох, бойлы, пучок опарыша, червь.
- **Лещ:** опарыш, мотыль, червь.
- **Прикормка:** готовая смесь, смоченная водой из водоёма, и немного насадки — зёрна кукурузы, опарыш.

## Как ловить

1. Сделайте 5–10 забросов полной кормушкой в одну точку — это стартовая прикормка.
2. Чтобы попадать в одно место, после первого заброса заведите леску за клипсу на шпуле и запомните ориентир на другом берегу.
3. Пока клёва нет, перезабрасывайте каждые 5–10 минут, потом — реже.
4. Поклёвка — вершинка резко дёргается или распрямляется. Подсекайте коротким движением удилища вверх и в сторону.

> Перед рыбалкой проверьте запреты и промысловую меру для водоёма в разделе «Правила и запреты».$md$,
   $md$Фидер — жем салғышы бар түпкі құрал: ол жемдеме мен жемді бір нүктеге жеткізеді. Алматы маңындағы Қапшағайда, Іледе, тоғандар мен ақылы тоғандарда бұл жағадан сазан, мөңке және табан балық аулаудың ең оңай тәсілі.

## Не жинау керек

- **Қармақсап** 3,6–3,9 м, салмағы 80–100 г-ға дейін. Жинақта қаттылығы әртүрлі бірнеше ауыстырмалы ұшы бар: олардың иілуінен балықтың қапқаны көрінеді.
- **Катушка** өлшемі 3000–4000.
- **Негізгі жіп:** 0,25–0,28 мм монобау немесе 0,12–0,14 мм өрме бау. Өрме бауға шок-лидер байлаңыз — 0,30–0,35 мм монобаудың 10–15 м: ол алысқа лақтырғандағы серпінді басады.
- **Жем салғыштар** 40–80 г: Іленің ағысында — ауырырақ, тоғанда — жеңілірек.
- **Жетекшілер** 0,16–0,20 мм жіптен 30–60 см, № 8–12 ілмектер.
- Қармақсапқа **тұғыр** және **сүзгі тор**.

## Құрастыру

Ең оңайы — сырғымалы жем салғыш. Карабиндегі жем салғыш негізгі жіп бойымен еркін жүреді, одан төмен — тоқтатқыш моншақ, айналмалы және ілмегі бар жетекші. Балық жемді алғанда жем салғыштың салмағын сезбейді дерлік.

## Жем және жемдеме

- **Сазан мен мөңке:** жүгері, бұршақ, бойлдар, бір шоқ опарыш, құрт.
- **Табан балық:** опарыш, мотыль, құрт.
- **Жемдеме:** су айдынының суымен ылғалдандырылған дайын қоспа және аздап жем — жүгері дәні, опарыш.

## Қалай аулау керек

1. Толы жем салғышпен бір нүктеге 5–10 рет лақтырыңыз — бұл бастапқы жемдеу.
2. Бір жерге дәл түсу үшін алғашқы лақтырудан кейін жіпті шпуладағы клипсаға іліп, қарсы жағадағы бағдарды есте сақтаңыз.
3. Балық қаппай тұрғанда әр 5–10 минут сайын қайта лақтырыңыз, кейін — сиректеу.
4. Балық қапқанда ұшы кенет тартылады немесе түзеледі. Қармақсапты қысқа қимылмен жоғары және бүйірге тартып ілдіріңіз.

> Балық аулауға шықпас бұрын су айдынына арналған тыйымдар мен кәсіптік өлшемді «Ережелер мен тыйымдар» бөлімінен тексеріңіз.$md$,
   $md$A feeder is a bottom rig with a feeder cage that delivers groundbait and bait to one spot. On Kapshagay, the Ile, ponds and paid ponds around Almaty, it is the easiest way to catch carp, crucian carp and bream from the bank.

## What you need

- **Rod** 3.6–3.9 m, casting weight up to 80–100 g. It comes with several interchangeable quiver tips of different stiffness: their bend shows the bite.
- **Reel** size 3000–4000.
- **Main line:** monofilament 0.25–0.28 mm or braid 0.12–0.14 mm. Tie a shock leader to braid — 10–15 m of 0.30–0.35 mm monofilament: it absorbs the jolt of a long cast.
- **Feeders** 40–80 g: heavier on the Ile current, lighter on a pond.
- **Hook lengths** 30–60 cm of 0.16–0.20 mm line, hooks size 8–12.
- A **rod rest** and a **landing net**.

## The rig

The simplest is a running feeder. The feeder on a snap slides freely along the main line, followed by a bead stop, a swivel and the hook length. The fish takes the bait and barely feels the feeder's weight.

## Bait and groundbait

- **Carp and crucian carp:** sweetcorn, peas, boilies, a bunch of maggots, worms.
- **Bream:** maggots, bloodworms, worms.
- **Groundbait:** a ready mix moistened with water from the lake or river, plus a little hook bait — corn, maggots.

## How to fish

1. Make 5–10 casts with a full feeder to one spot — this is your initial groundbaiting.
2. To hit the same spot every time, clip the line on the spool after the first cast and remember a landmark on the far bank.
3. Recast every 5–10 minutes until the fish start biting, then less often.
4. A bite is a sharp pull or straightening of the tip. Strike with a short upward and sideways movement of the rod.

> Before you go, check the bans and minimum sizes for the water in Rules and bans.$md$),
  ('three_knots',
   'knots',
   50,
   date '2026-09-30',
   $md$Три узла на весь сезон$md$,
   $md$Бүкіл маусымға үш түйін$md$,
   $md$Three knots for the whole season$md$,
   $md$Улучшенный клинч, паломар и хирургическая петля — чтобы привязать крючок, вертлюжок и поводок.$md$,
   $md$Жетілдірілген клинч, паломар және хирургиялық ілмек — ілмекті, айналмалыны және жетекшіні байлау үшін.$md$,
   $md$The improved clinch, the Palomar and the surgeon's loop — to tie on hooks, swivels and hook lengths.$md$,
   $md$Большинство сходов рыбы — из-за плохо завязанного узла. Этих трёх хватит почти для любой снасти.

Перед затягиванием смачивайте узел водой: сухая леска нагревается от трения и теряет прочность. Затягивайте медленно и плотно, кончик обрезайте, оставляя 2–3 мм.

## Улучшенный клинч

Для крючков, вертлюжков и приманок на монолеске.

1. Проденьте леску в ушко.
2. Сделайте свободным концом 5–7 оборотов вокруг основной лески.
3. Проденьте конец в первую петлю у самого ушка.
4. Затем — в большую петлю, которая получилась сбоку.
5. Смочите и затяните, потянув за основную леску.

## Паломар

Один из самых прочных простых узлов, подходит и для плетёного шнура.

1. Сложите леску вдвое и проденьте петлю в ушко.
2. Завяжите сложенной леской простой узел, не затягивая.
3. Проведите крючок или приманку через петлю.
4. Смочите и затяните, потянув за оба конца.

## Хирургическая петля

Петля на конце поводка или основной лески — для соединения «петля в петлю».

1. Сложите конец лески вдвое.
2. Завяжите сложенной леской простой узел.
3. Проденьте петлю через узел ещё раз.
4. Смочите и затяните.

## Петля в петлю

Так поводки меняются за секунды. Проденьте петлю основной лески в петлю поводка, затем пропустите через петлю основной лески весь поводок с крючком и затяните.

> Потренируйтесь дома: на холоде, на ветру и в темноте узлы вяжутся хуже.$md$,
   $md$Балықты жіберіп алудың көбі нашар байланған түйіннен болады. Осы үшеуі кез келген құралға жетіп жатыр.

Тартып бекітер алдында түйінді сумен сулаңыз: құрғақ жіп үйкелістен қызып, беріктігін жоғалтады. Баяу әрі тығыз тартыңыз, ұшын 2–3 мм қалдырып кесіңіз.

## Жетілдірілген клинч

Монобаудағы ілмектер, айналмалылар мен жасанды жемдер үшін.

1. Жіпті ілмектің көзінен өткізіңіз.
2. Бос ұшымен негізгі жіпті 5–7 рет орап шығыңыз.
3. Ұшын көздің дәл жанындағы бірінші ілмекке өткізіңіз.
4. Содан кейін — бүйірде пайда болған үлкен ілмекке.
5. Сулап, негізгі жіпті тартып бекітіңіз.

## Паломар

Ең берік қарапайым түйіндердің бірі, өрме бауға да жарайды.

1. Жіпті екі есе бүктеп, ілмегін көзден өткізіңіз.
2. Бүктелген жіппен тартпай қарапайым түйін байлаңыз.
3. Ілмекті немесе жасанды жемді ілмек арқылы өткізіңіз.
4. Сулап, екі ұшынан тартып бекітіңіз.

## Хирургиялық ілмек

Жетекшінің немесе негізгі жіптің ұшындағы ілмек — «ілмекке ілмек» қосу үшін.

1. Жіптің ұшын екі есе бүктеңіз.
2. Бүктелген жіппен қарапайым түйін байлаңыз.
3. Ілмекті түйіннен тағы бір рет өткізіңіз.
4. Сулап, тартып бекітіңіз.

## Ілмекке ілмек

Осылай жетекшілер бірнеше секундта ауыстырылады. Негізгі жіптің ілмегін жетекшінің ілмегінен өткізіп, содан кейін бүкіл жетекшіні ілмегімен бірге негізгі жіптің ілмегінен өткізіп, тартыңыз.

> Үйде жаттығыңыз: суықта, желде және қараңғыда түйін байлау қиынырақ.$md$,
   $md$Most lost fish come from a badly tied knot. These three cover almost any rig.

Wet the knot with water before tightening: dry line heats up from friction and loses strength. Tighten slowly and firmly and trim the tag end, leaving 2–3 mm.

## Improved clinch knot

For hooks, swivels and lures on monofilament.

1. Pass the line through the eye.
2. Wrap the tag end around the main line 5–7 times.
3. Pass the end through the first loop next to the eye.
4. Then through the big loop that has formed at the side.
5. Wet it and tighten by pulling the main line.

## Palomar knot

One of the strongest simple knots, good for braid too.

1. Double the line and pass the loop through the eye.
2. Tie a simple overhand knot with the doubled line without tightening it.
3. Pass the hook or lure through the loop.
4. Wet it and tighten by pulling both ends.

## Surgeon's loop

A loop at the end of a hook length or the main line, for loop-to-loop connections.

1. Double the end of the line.
2. Tie an overhand knot with the doubled line.
3. Pass the loop through the knot once more.
4. Wet it and tighten.

## Loop to loop

This lets you change hook lengths in seconds. Pass the main line loop through the hook length loop, then pull the whole hook length with the hook through the main line loop and tighten.

> Practise at home: knots are harder to tie in the cold, in the wind and in the dark.$md$),
  ('fish_on_coals',
   'cooking',
   60,
   date '2026-09-30',
   $md$Рыба на углях$md$,
   $md$Шоқта пісірілген балық$md$,
   $md$Fish on hot coals$md$,
   $md$Простой способ приготовить улов у воды — на решётке или в фольге.$md$,
   $md$Ауланған балықты су жағасында пісірудің қарапайым тәсілі — торда немесе фольгада.$md$,
   $md$A simple way to cook your catch by the water — on a grill or in foil.$md$,
   $md$Свежая рыба, приготовленная у воды, — лучшая награда за день на водоёме. Нужны угли, решётка или фольга и полчаса.

## Подготовка

1. После поимки держите рыбу живой в садке или сразу уберите в тень, лучше — в сумку-холодильник.
2. Почистите от чешуи, выпотрошите, удалите жабры и промойте.
3. У сазана и леща много мелких костей: сделайте поперечные надрезы через каждые 1–2 см — так они лучше пропекутся.
4. Посолите и поперчите внутри и снаружи. В брюшко положите лимон, лук, зелень.

## На решётке

Дождитесь, пока дрова прогорят и угли покроются белым налётом: открытого огня быть не должно. Смажьте решётку маслом, чтобы кожа не прилипла. Рыбу весом 0,5–1 кг жарьте на высоте 10–15 см от углей по 8–12 минут с каждой стороны.

## В фольге

Заверните рыбу с маслом, луком и лимоном в два слоя фольги и положите прямо на угли на 20–30 минут, перевернув один-два раза.

## Готова ли рыба

Мясо у самой кости должно быть белым, непрозрачным и легко отделяться. Речную и озёрную рыбу не ешьте сырой и недожаренной — в ней бывают паразиты.

## После ужина

- Разводите костёр только там, где это разрешено. В нацпарках — только в оборудованных местах; в сухой сезон огонь могут запретить совсем.
- Залейте кострище водой и перемешайте угли, пока они не перестанут шипеть.
- Чешую, внутренности и мусор заберите с собой.$md$,
   $md$Су жағасында пісірілген жаңа балық — су айдынында өткізген күннің ең жақсы сыйы. Шоқ, тор немесе фольга және жарты сағат керек.

## Дайындау

1. Ауланған балықты садокта тірідей ұстаңыз немесе бірден көлеңкеге, жақсысы — салқындатқыш сөмкеге салыңыз.
2. Қабыршағын тазалап, ішін ақтарыңыз, желбезегін алып, жуыңыз.
3. Сазан мен табан балықта ұсақ сүйек көп: әр 1–2 см сайын көлденең тіліңіз — сонда олар жақсырақ піседі.
4. Ішін де, сыртын да тұздап, бұрыш сеуіп қойыңыз. Қарнына лимон, пияз, көк салыңыз.

## Торда

Отын жанып біткенше және шоқ ақ күлмен жабылғанша күтіңіз: ашық жалын болмауы керек. Балықтың терісі жабыспас үшін торды маймен майлаңыз. Салмағы 0,5–1 кг балықты шоқтан 10–15 см биіктікте әр жағын 8–12 минуттан қуырыңыз.

## Фольгада

Балықты маймен, пиязбен және лимонмен бірге фольгаға екі қабат орап, тура шоқтың үстіне 20–30 минутқа қойыңыз, бір-екі рет аударыңыз.

## Балық пісті ме

Сүйектің дәл жанындағы еті ақ, мөлдір емес болып, оңай ажырауы керек. Өзен мен көл балығын шикі және шала піскен күйінде жемеңіз — онда паразиттер болады.

## Кешкі астан кейін

- Отты тек рұқсат етілген жерде жағыңыз. Ұлттық парктерде — тек жабдықталған орындарда; құрғақ маусымда от жағуға мүлдем тыйым салынуы мүмкін.
- Ошақты сумен сөндіріп, шоқ шыжылдауын тоқтатқанша араластырыңыз.
- Қабыршақты, ішек-қарынды және қоқысты өзіңізбен алып кетіңіз.$md$,
   $md$Fresh fish cooked by the water is the best reward for a day out. All you need is hot coals, a grill or foil and half an hour.

## Preparing the fish

1. After catching, keep the fish alive in a keepnet or put it in the shade right away, ideally in a cool bag.
2. Scale and gut it, remove the gills and rinse.
3. Carp and bream have many small bones: make cross cuts every 1–2 cm so they cook through better.
4. Season with salt and pepper inside and out. Put lemon, onion and herbs in the belly.

## On a grill

Wait until the wood burns down and the coals are covered with white ash: there should be no open flame. Oil the grill so the skin does not stick. Cook a 0.5–1 kg fish 10–15 cm above the coals for 8–12 minutes on each side.

## In foil

Wrap the fish with oil, onion and lemon in two layers of foil and put it straight on the coals for 20–30 minutes, turning once or twice.

## Is it done?

The flesh next to the bone should be white, opaque and come away easily. Do not eat river or lake fish raw or undercooked — it can carry parasites.

## After dinner

- Light a fire only where it is allowed. In national parks, only at designated fire spots; in the dry season fires may be banned altogether.
- Pour water over the fire pit and stir the coals until they stop hissing.
- Take the scales, guts and litter with you.$md$);
