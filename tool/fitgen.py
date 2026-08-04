# -*- coding: utf-8 -*-
"""Generates lib/data/exercises_data.dart plus the matching en/ru l10n keys.

Run from the project root:  python tool/fitgen.py

The tables below are the single source of truth for the SigmaFit catalogue.
Generating the Dart data AND both dictionaries from one spec is what stops the
languages drifting apart — every exercise gets its en+ru name and technique cue
in the same row, so a missing translation is impossible by construction.
"""
import io

# id, EN name, RU name, EN technique cue, RU technique cue, icon, motion
EX = [
    # ── existing (ids/keys preserved so their l10n entries keep working) ──
    ('squat', 'Squat', 'Приседания', 'Chest up, knees track over toes.', 'Спина ровно, колени вдоль стоп.', 'accessibility_new_rounded', 'squat'),
    ('pushup', 'Push-up', 'Отжимания', 'Elbows back, body in one line.', 'Локти назад, тело одной линией.', 'fitness_center_rounded', 'pushup'),
    ('lunge', 'Lunge', 'Выпады', 'Front knee over ankle, torso tall.', 'Колено над стопой, корпус прямо.', 'directions_walk_rounded', 'lunge'),
    ('plank', 'Plank', 'Планка', 'Squeeze glutes, hips level.', 'Напрягите ягодицы, бёдра ровно.', 'horizontal_rule_rounded', 'plank'),
    ('mountain_climber', 'Mountain climber', 'Скалолаз', 'Hips low, drive knees fast.', 'Бёдра низко, колени быстро.', 'terrain_rounded', 'core'),
    ('glute_bridge', 'Glute bridge', 'Мостик', 'Push through heels, squeeze at the top.', 'Через пятки, сжать в верхней точке.', 'self_improvement_rounded', 'squat'),
    ('jump_in_place', 'Jump in place', 'Прыжки на месте', 'Land softly through the whole foot.', 'Мягко на всю стопу.', 'directions_run_rounded', 'jump'),
    ('sumo_squat', 'Sumo squat', 'Приседания сумо', 'Wide stance, toes turned out.', 'Ноги широко, носки в стороны.', 'accessibility_new_rounded', 'squat'),
    ('reverse_lunge', 'Reverse lunge', 'Обратные выпады', 'Step back, weight on the front leg.', 'Шаг назад, вес на передней ноге.', 'directions_walk_rounded', 'lunge'),
    ('jumping_jack', 'Jumping jack', 'Прыжки «звёздочка»', 'Arms fully overhead, steady rhythm.', 'Руки над головой, ровный ритм.', 'accessibility_rounded', 'jump'),
    ('high_knees', 'High knees', 'Бег с высоким подъёмом колен', 'Knees to hip height, stay light.', 'Колени до уровня бёдер, легко.', 'directions_run_rounded', 'jump'),
    ('burpee', 'Burpee', 'Бёрпи', 'Chest to floor, explode up.', 'Грудь к полу, взрывной выход.', 'whatshot_rounded', 'jump'),
    ('jump_squat', 'Jump squat', 'Приседания с прыжком', 'Sit back, jump tall, land soft.', 'Присед назад, прыжок вверх, мягко.', 'arrow_upward_rounded', 'jump'),
    ('high_knee_march', 'High knee march', 'Ходьба с подъёмом колен', 'Controlled pace, tall posture.', 'Спокойный темп, корпус прямо.', 'directions_walk_rounded', 'jump'),
    ('skater_jump', 'Skater jump', 'Прыжки конькобежца', 'Push side to side, land on one leg.', 'Толчок в сторону, приземление на одну.', 'swap_horiz_rounded', 'jump'),
    ('side_shuffle', 'Side shuffle', 'Приставные шаги', 'Stay low, quick feet.', 'Ниже центр тяжести, быстрые стопы.', 'compare_arrows_rounded', 'lunge'),
    ('crunches', 'Crunches', 'Скручивания', 'Lift with the abs, not the neck.', 'Поднимайтесь прессом, не шеей.', 'rotate_right_rounded', 'core'),
    ('bicycle', 'Bicycle crunch', 'Велосипед', 'Elbow to the opposite knee, slowly.', 'Локоть к противоположному колену.', 'pedal_bike_rounded', 'core'),
    ('leg_raise', 'Leg raise', 'Подъём ног', 'Lower back pressed to the floor.', 'Поясница прижата к полу.', 'height_rounded', 'core'),
    ('side_plank', 'Side plank', 'Боковая планка', 'Stack the shoulders, lift the hip.', 'Плечи в линию, бедро вверх.', 'swap_horiz_rounded', 'plank'),
    ('superman', 'Superman', 'Гиперэкстензия лёжа', 'Lift chest and thighs together.', 'Грудь и бёдра вверх одновременно.', 'airline_seat_flat_rounded', 'core'),
    ('russian_twist', 'Russian twist', 'Русские скручивания', 'Rotate from the waist, chest open.', 'Поворот от корпуса, грудь раскрыта.', 'sync_alt_rounded', 'core'),
    ('flutter_kicks', 'Flutter kicks', 'Ножницы вертикальные', 'Small fast kicks, core tight.', 'Мелкие быстрые махи, пресс напряжён.', 'waves_rounded', 'core'),

    # ── chest ──
    ('knee_pushup', 'Knee push-up', 'Отжимания с колен', 'Straight line from knees to head.', 'Прямая линия от колен до головы.', 'fitness_center_rounded', 'pushup'),
    ('incline_pushup', 'Incline push-up', 'Отжимания от возвышения', 'Hands on a bench — an easier angle.', 'Руки на опоре, угол легче.', 'stairs_rounded', 'pushup'),
    ('decline_pushup', 'Decline push-up', 'Отжимания с ногами на опоре', 'Feet raised, more load on the chest.', 'Ноги на опоре, больше нагрузки на грудь.', 'north_rounded', 'pushup'),
    ('wide_pushup', 'Wide push-up', 'Широкие отжимания', 'Hands wider, elbows out at 45°.', 'Руки шире, локти под 45°.', 'open_with_rounded', 'pushup'),
    ('diamond_pushup', 'Diamond push-up', 'Отжимания «алмаз»', 'Hands together, elbows tight.', 'Руки вместе, локти близко к телу.', 'change_history_rounded', 'pushup'),
    ('pushup_hold', 'Push-up hold', 'Удержание в отжимании', 'Hold halfway down, keep breathing.', 'Держите середину, дышите.', 'timer_rounded', 'plank'),
    ('chest_fly_dumbbell', 'Dumbbell fly', 'Разведение с гантелями', 'Slight elbow bend, wide arc.', 'Локти чуть согнуты, широкая дуга.', 'fitness_center_rounded', 'pushup'),
    ('bench_press_barbell', 'Barbell bench press', 'Жим штанги лёжа', 'Shoulder blades tight, bar to the chest.', 'Лопатки сведены, штанга к груди.', 'monitor_weight_rounded', 'pushup'),

    # ── arms ──
    ('triceps_dip', 'Triceps dip', 'Отжимания на трицепс от опоры', 'Elbows back, not flared out.', 'Локти назад, не в стороны.', 'chair_rounded', 'pushup'),
    ('biceps_curl', 'Biceps curl', 'Подъём на бицепс', 'Elbows pinned to the sides.', 'Локти прижаты к корпусу.', 'fitness_center_rounded', 'pushup'),
    ('hammer_curl', 'Hammer curl', 'Молотковый подъём', 'Neutral grip, no swinging.', 'Нейтральный хват, без раскачки.', 'fitness_center_rounded', 'pushup'),
    ('triceps_extension', 'Overhead triceps extension', 'Французский жим стоя', 'Elbows point forward, lower slowly.', 'Локти вперёд, опускайте медленно.', 'vertical_align_top_rounded', 'pushup'),
    ('arm_circles', 'Arm circles', 'Круги руками', 'Small to large, both directions.', 'От малых к большим, в обе стороны.', 'autorenew_rounded', 'jump'),

    # ── shoulders ──
    ('pike_pushup', 'Pike push-up', 'Отжимания «уголок»', 'Hips high, crown toward the floor.', 'Бёдра высоко, макушка к полу.', 'change_history_rounded', 'pushup'),
    ('shoulder_tap', 'Plank shoulder tap', 'Планка с касанием плеч', 'Hips still, tap slowly.', 'Бёдра неподвижны, касайтесь плавно.', 'pan_tool_rounded', 'plank'),
    ('lateral_raise', 'Lateral raise', 'Разведение рук в стороны', 'Lead with the elbows, to shoulder height.', 'Ведите локтями, до уровня плеч.', 'open_with_rounded', 'pushup'),
    ('front_raise', 'Front raise', 'Подъём рук перед собой', 'Straight arms, no momentum.', 'Руки прямые, без рывка.', 'north_rounded', 'pushup'),
    ('overhead_press', 'Overhead press', 'Жим над головой', 'Ribs down, press straight up.', 'Рёбра вниз, жим строго вверх.', 'vertical_align_top_rounded', 'pushup'),

    # ── back ──
    ('bird_dog', 'Bird dog', '«Птица-собака»', 'Opposite arm and leg, hips square.', 'Противоположные рука и нога, бёдра ровно.', 'all_inclusive_rounded', 'core'),
    ('reverse_snow_angel', 'Reverse snow angel', 'Обратный «ангел»', 'Arms sweep wide, chest off the floor.', 'Руки по широкой дуге, грудь от пола.', 'blur_on_rounded', 'core'),
    ('pull_up', 'Pull-up', 'Подтягивания', 'Pull the chest to the bar, no swing.', 'Тяните грудь к перекладине, без раскачки.', 'fitness_center_rounded', 'pushup'),
    ('chin_up', 'Chin-up', 'Подтягивания обратным хватом', 'Palms toward you, full hang at the bottom.', 'Ладони к себе, полный вис внизу.', 'fitness_center_rounded', 'pushup'),
    ('australian_pullup', 'Australian pull-up', 'Австралийские подтягивания', 'Body straight, chest to the bar.', 'Тело прямое, грудь к перекладине.', 'horizontal_rule_rounded', 'pushup'),
    ('dumbbell_row', 'Dumbbell row', 'Тяга гантели в наклоне', 'Flat back, pull toward the hip.', 'Спина ровная, тяга к бедру.', 'rowing_rounded', 'pushup'),
    ('good_morning', 'Good morning', 'Наклоны со штангой', 'Hinge at the hips, back neutral.', 'Наклон от бёдер, спина нейтральна.', 'south_rounded', 'squat'),

    # ── legs ──
    ('wall_sit', 'Wall sit', 'Присед у стены', 'Thighs parallel, back flat on the wall.', 'Бёдра параллельно, спина к стене.', 'crop_square_rounded', 'plank'),
    ('bulgarian_split_squat', 'Bulgarian split squat', 'Болгарские выпады', 'Rear foot elevated, drop straight down.', 'Задняя нога на опоре, вниз строго.', 'stairs_rounded', 'lunge'),
    ('step_up', 'Step-up', 'Зашагивания на опору', 'Drive through the top leg only.', 'Работает только верхняя нога.', 'stairs_rounded', 'lunge'),
    ('calf_raise', 'Calf raise', 'Подъём на носки', 'Full range, pause at the top.', 'Полная амплитуда, пауза сверху.', 'keyboard_double_arrow_up_rounded', 'squat'),
    ('goblet_squat', 'Goblet squat', 'Приседания с гантелью у груди', 'Weight at the chest, elbows inside the knees.', 'Вес у груди, локти внутри колен.', 'monitor_weight_rounded', 'squat'),
    ('barbell_squat', 'Barbell back squat', 'Приседания со штангой', 'Brace the core, knees out.', 'Напрягите корпус, колени в стороны.', 'monitor_weight_rounded', 'squat'),
    ('romanian_deadlift', 'Romanian deadlift', 'Румынская тяга', 'Push the hips back, feel the hamstrings.', 'Бёдра назад, тянет заднюю поверхность.', 'south_rounded', 'squat'),
    ('single_leg_deadlift', 'Single-leg deadlift', 'Тяга на одной ноге', 'Hips square, slow and balanced.', 'Бёдра ровно, медленно и в балансе.', 'straighten_rounded', 'squat'),
    ('curtsy_lunge', 'Curtsy lunge', 'Выпад-реверанс', 'Step behind and across, knee down.', 'Шаг назад по диагонали, колено вниз.', 'swap_horiz_rounded', 'lunge'),

    # ── glutes ──
    ('hip_thrust', 'Hip thrust', 'Подъём бёдер с опорой', 'Shoulders on the bench, chin tucked.', 'Плечи на опоре, подбородок к груди.', 'self_improvement_rounded', 'squat'),
    ('donkey_kick', 'Donkey kick', 'Махи ногой назад', 'Heel to the ceiling, no arching.', 'Пятка в потолок, без прогиба в пояснице.', 'north_rounded', 'core'),
    ('fire_hydrant', 'Fire hydrant', 'Отведение ноги в сторону', 'Open the knee out, hips still.', 'Колено в сторону, бёдра неподвижны.', 'open_with_rounded', 'core'),
    ('kickback', 'Standing kickback', 'Махи назад стоя', 'Squeeze at the top, stay tall.', 'Сжать в верхней точке, корпус прямо.', 'south_rounded', 'core'),
    ('frog_pump', 'Frog pump', 'Мостик «лягушка»', 'Heels together, knees wide.', 'Пятки вместе, колени широко.', 'self_improvement_rounded', 'squat'),
    ('glute_bridge_march', 'Glute bridge march', 'Мостик с попеременным подъёмом', 'Hold the bridge, lift one knee.', 'Держите мостик, поднимайте колено.', 'all_inclusive_rounded', 'squat'),
    ('clamshell', 'Clamshell', '«Ракушка»', 'Feet together, open the top knee.', 'Стопы вместе, раскрывайте верхнее колено.', 'unfold_more_rounded', 'core'),

    # ── abs / waist ──
    ('dead_bug', 'Dead bug', '«Мёртвый жук»', 'Lower back glued down, move slowly.', 'Поясница прижата, движение медленное.', 'airline_seat_flat_rounded', 'core'),
    ('hollow_hold', 'Hollow hold', 'Удержание «лодочка»', 'Ribs down, low back flat.', 'Рёбра вниз, поясница ровно.', 'timer_rounded', 'core'),
    ('v_up', 'V-up', 'Складка', 'Reach hands to feet, exhale up.', 'Руки к стопам, выдох на подъёме.', 'change_history_rounded', 'core'),
    ('toe_touch', 'Toe touch', 'Касание носков', 'Legs up, reach with the shoulders.', 'Ноги вверх, тянитесь плечами.', 'vertical_align_top_rounded', 'core'),
    ('heel_taps', 'Heel taps', 'Касание пяток', 'Small side reaches, ribs down.', 'Короткие наклоны в стороны, рёбра вниз.', 'compare_arrows_rounded', 'core'),
    ('oblique_crunch', 'Oblique crunch', 'Скручивания на бок', 'Elbow toward the same-side hip.', 'Локоть к бедру той же стороны.', 'rotate_right_rounded', 'core'),
    ('side_bend', 'Standing side bend', 'Наклоны в стороны стоя', 'Bend straight sideways, no rotation.', 'Наклон строго в сторону, без поворота.', 'swap_horiz_rounded', 'core'),
    ('scissor_kick', 'Scissor kick', 'Ножницы горизонтальные', 'Cross the legs, keep them low.', 'Скрещивайте ноги, держите низко.', 'waves_rounded', 'core'),
    ('plank_up_down', 'Plank up-down', 'Планка с подъёмом на руки', 'Alternate forearms and hands.', 'Чередуйте предплечья и ладони.', 'unfold_more_rounded', 'plank'),

    # ── forearms / grip ──
    ('wrist_curl', 'Wrist curl', 'Сгибание кистей', 'Forearms fixed, move only the wrists.', 'Предплечья зафиксированы, работают кисти.', 'pan_tool_rounded', 'pushup'),
    ('reverse_wrist_curl', 'Reverse wrist curl', 'Разгибание кистей', 'Palms down, slow and light.', 'Ладони вниз, медленно и с малым весом.', 'back_hand_rounded', 'pushup'),
    ('dead_hang', 'Dead hang', 'Вис на перекладине', 'Relax the shoulders, keep breathing.', 'Расслабьте плечи, дышите.', 'vertical_align_top_rounded', 'plank'),
    ('farmer_carry', 'Farmer carry', 'Прогулка фермера', 'Tall posture, walk steady.', 'Корпус прямо, шаг ровный.', 'hiking_rounded', 'plank'),

    # ── neck ──
    ('neck_tilt', 'Neck tilt', 'Наклоны головы', 'Ear to shoulder, never force it.', 'Ухо к плечу, без усилия.', 'psychology_rounded', 'core'),
    ('neck_rotation', 'Neck rotation', 'Повороты головы', 'Turn slowly, stop at tension.', 'Поворот медленно, до натяжения.', 'autorenew_rounded', 'core'),
    ('chin_tuck', 'Chin tuck', 'Втягивание подбородка', 'Slide the chin back, lengthen the neck.', 'Подбородок назад, шея вытянута.', 'south_rounded', 'core'),

    # ── HIIT / cardio ──
    ('sprint_in_place', 'Sprint in place', 'Спринт на месте', 'Maximum pace, short bursts.', 'Максимальный темп короткими сериями.', 'bolt_rounded', 'jump'),
    ('tuck_jump', 'Tuck jump', 'Прыжок с поджатыми коленями', 'Knees to chest, land soft.', 'Колени к груди, мягкое приземление.', 'arrow_upward_rounded', 'jump'),
    ('plank_jack', 'Plank jack', 'Планка с прыжком ног', 'Hips quiet, feet jump wide.', 'Бёдра стабильны, стопы в стороны.', 'horizontal_rule_rounded', 'plank'),
    ('squat_thrust', 'Squat thrust', 'Выброс ног из приседа', 'Hands down, feet back and in.', 'Руки в пол, ноги назад и обратно.', 'whatshot_rounded', 'jump'),
    ('lateral_hop', 'Lateral hop', 'Прыжки в сторону', 'Quick side hops, stay low.', 'Быстрые прыжки в сторону, ниже центр.', 'compare_arrows_rounded', 'jump'),
    ('star_jump', 'Star jump', 'Прыжок «звезда»', 'Explode wide, land under control.', 'Раскройтесь широко, приземление под контролем.', 'accessibility_rounded', 'jump'),
    ('shadow_box', 'Shadow boxing', 'Бой с тенью', 'Loose shoulders, fast hands.', 'Плечи свободны, руки быстро.', 'sports_martial_arts_rounded', 'jump'),
    ('bear_crawl', 'Bear crawl', 'Ходьба медведем', 'Knees off the floor, small steps.', 'Колени над полом, мелкие шаги.', 'sports_gymnastics_rounded', 'plank'),
    ('crab_walk', 'Crab walk', 'Ходьба раком', 'Hips up, opposite hand and foot.', 'Бёдра вверх, рука и нога навстречу.', 'sports_gymnastics_rounded', 'plank'),

    # ── warm-up / mobility ──
    ('jog_in_place', 'Jog in place', 'Бег на месте', 'Easy pace — just get warm.', 'Легкий темп, только разогрев.', 'directions_run_rounded', 'jump'),
    ('shoulder_roll', 'Shoulder roll', 'Вращение плечами', 'Big slow circles, both ways.', 'Большие медленные круги в обе стороны.', 'autorenew_rounded', 'jump'),
    ('hip_circle', 'Hip circle', 'Вращение бёдрами', 'Wide circles, feet planted.', 'Широкие круги, стопы на месте.', 'loop_rounded', 'squat'),
    ('leg_swing', 'Leg swing', 'Махи ногой', 'Relaxed swings, hold a support.', 'Свободные махи, держитесь за опору.', 'swap_horiz_rounded', 'lunge'),
    ('torso_twist', 'Torso twist', 'Повороты корпуса', 'Rotate from the ribs, hips still.', 'Поворот от рёбер, бёдра на месте.', 'sync_alt_rounded', 'core'),
    ('ankle_circle', 'Ankle circle', 'Вращение стопой', 'Slow circles, both directions.', 'Медленные круги в обе стороны.', 'loop_rounded', 'squat'),
    ('cat_cow', 'Cat-cow', '«Кошка-корова»', 'Arch and round with the breath.', 'Прогиб и округление на дыхании.', 'all_inclusive_rounded', 'core'),

    # ── stretching ──
    ('hamstring_stretch', 'Hamstring stretch', 'Растяжка задней поверхности бедра', 'Hinge forward, soft knees.', 'Наклон от бёдер, колени мягкие.', 'south_rounded', 'plank'),
    ('quad_stretch', 'Quad stretch', 'Растяжка квадрицепса', 'Heel to glute, knee pointing down.', 'Пятка к ягодице, колено вниз.', 'north_rounded', 'plank'),
    ('chest_stretch', 'Chest stretch', 'Растяжка груди', 'Hands behind you, open the chest.', 'Руки назад, раскройте грудь.', 'open_with_rounded', 'plank'),
    ('shoulder_stretch', 'Shoulder stretch', 'Растяжка плеча', 'Arm across the chest, gentle pull.', 'Рука перед грудью, мягкое натяжение.', 'front_hand_rounded', 'plank'),
    ('hip_flexor_stretch', 'Hip flexor stretch', 'Растяжка сгибателей бедра', 'Tuck the pelvis, press forward.', 'Подкрутите таз, подайтесь вперёд.', 'directions_walk_rounded', 'plank'),
    ('seated_twist', 'Seated twist', 'Скрутка сидя', 'Sit tall, rotate on the exhale.', 'Спина прямая, поворот на выдохе.', 'sync_alt_rounded', 'plank'),
    ('calf_stretch', 'Calf stretch', 'Растяжка икры', 'Back heel down, front knee bent.', 'Задняя пятка в пол, переднее колено согнуто.', 'keyboard_double_arrow_up_rounded', 'plank'),
    ('butterfly_stretch', 'Butterfly stretch', 'Растяжка «бабочка»', 'Soles together, let the knees sink.', 'Стопы вместе, колени вниз.', 'spa_rounded', 'plank'),
    ('child_pose', "Child's pose", 'Поза ребёнка', 'Hips to heels, arms long.', 'Бёдра к пяткам, руки вперёд.', 'spa_rounded', 'plank'),
    ('cobra_stretch', 'Cobra stretch', 'Поза кобры', 'Press the chest up, shoulders down.', 'Грудь вверх, плечи вниз.', 'north_rounded', 'plank'),
    ('neck_stretch', 'Neck stretch', 'Растяжка шеи', 'Gentle — never force the range.', 'Мягко, без насилия над амплитудой.', 'psychology_rounded', 'plank'),

    # ── yoga / pilates ──
    ('downward_dog', 'Downward dog', 'Поза собаки мордой вниз', 'Long spine, heels reaching down.', 'Вытянутая спина, пятки тянутся вниз.', 'change_history_rounded', 'plank'),
    ('warrior_two', 'Warrior II', 'Поза воина II', 'Front knee over ankle, arms wide.', 'Колено над стопой, руки в линию.', 'accessibility_rounded', 'lunge'),
    ('tree_pose', 'Tree pose', 'Поза дерева', 'Fix your gaze, press foot to leg.', 'Фиксируйте взгляд, стопа прижата к ноге.', 'spa_rounded', 'plank'),
    ('bridge_pose', 'Bridge pose', 'Поза моста', 'Feet parallel, lift the chest.', 'Стопы параллельно, грудь вверх.', 'self_improvement_rounded', 'squat'),
    ('pilates_hundred', 'Pilates hundred', 'Пилатес «сотня»', 'Pump the arms, breathe in fives.', 'Пульсация руками, дыхание на пять счётов.', 'waves_rounded', 'core'),
    ('pilates_leg_circle', 'Pilates leg circle', 'Пилатес круги ногой', 'Small circles, pelvis still.', 'Малые круги, таз неподвижен.', 'loop_rounded', 'core'),
    ('pilates_roll_up', 'Pilates roll-up', 'Пилатес роллап', 'Peel up one vertebra at a time.', 'Поднимайтесь позвонок за позвонком.', 'unfold_more_rounded', 'core'),
    ('pilates_swimming', 'Pilates swimming', 'Пилатес «плавание»', 'Opposite arm and leg, long spine.', 'Противоположные рука и нога, спина длинная.', 'waves_rounded', 'core'),
]

# id, EN title, RU title, icon, gender, level, equipment, work, rest, sets, kcal/min, exercise ids
ROUTINES = [
    ('full_body', 'Full body', 'Всё тело', 'fitness_center_rounded', 'both', 'beginner', 'none', 40, 15, 2, 8,
     ['squat', 'pushup', 'lunge', 'plank', 'mountain_climber', 'glute_bridge', 'jump_in_place', 'sumo_squat', 'reverse_lunge']),
    ('cardio', 'Cardio', 'Кардио', 'favorite_rounded', 'both', 'intermediate', 'none', 30, 15, 2, 11,
     ['jumping_jack', 'high_knees', 'burpee', 'mountain_climber', 'jump_squat', 'high_knee_march', 'skater_jump', 'side_shuffle']),
    ('core', 'Abs', 'Пресс', 'crop_square_rounded', 'both', 'beginner', 'none', 35, 10, 2, 7,
     ['plank', 'crunches', 'bicycle', 'leg_raise', 'side_plank', 'superman', 'russian_twist', 'flutter_kicks']),
    ('warmup', 'Warm-up', 'Разминка', 'autorenew_rounded', 'both', 'beginner', 'none', 25, 5, 1, 4,
     ['jog_in_place', 'shoulder_roll', 'arm_circles', 'hip_circle', 'leg_swing', 'torso_twist', 'ankle_circle', 'cat_cow']),
    ('stretching', 'Stretching', 'Растяжка', 'spa_rounded', 'both', 'beginner', 'none', 35, 5, 1, 3,
     ['hamstring_stretch', 'quad_stretch', 'chest_stretch', 'shoulder_stretch', 'hip_flexor_stretch', 'seated_twist', 'calf_stretch', 'butterfly_stretch', 'child_pose', 'cobra_stretch']),
    ('mobility', 'Mobility', 'Мобильность', 'all_inclusive_rounded', 'both', 'beginner', 'none', 30, 8, 1, 4,
     ['cat_cow', 'hip_circle', 'ankle_circle', 'torso_twist', 'bird_dog', 'leg_swing', 'shoulder_roll', 'seated_twist']),
    ('home', 'Home workout', 'Домашняя тренировка', 'crop_square_rounded', 'both', 'beginner', 'none', 35, 15, 2, 8,
     ['squat', 'knee_pushup', 'glute_bridge', 'plank', 'reverse_lunge', 'crunches', 'superman', 'calf_raise']),
    ('gym', 'Gym workout', 'Тренировка в зале', 'monitor_weight_rounded', 'both', 'intermediate', 'barbell', 45, 30, 3, 7,
     ['barbell_squat', 'bench_press_barbell', 'dumbbell_row', 'overhead_press', 'romanian_deadlift', 'plank']),
    ('hiit', 'HIIT', 'HIIT', 'bolt_rounded', 'both', 'advanced', 'none', 25, 10, 3, 14,
     ['burpee', 'sprint_in_place', 'tuck_jump', 'plank_jack', 'squat_thrust', 'lateral_hop', 'star_jump', 'jump_squat']),

    # men
    ('chest', 'Chest', 'Грудь', 'fitness_center_rounded', 'male', 'intermediate', 'none', 35, 20, 3, 7,
     ['pushup', 'wide_pushup', 'diamond_pushup', 'incline_pushup', 'decline_pushup', 'pushup_hold', 'chest_stretch']),
    ('arms', 'Arms', 'Руки', 'fitness_center_rounded', 'male', 'intermediate', 'dumbbells', 35, 20, 3, 6,
     ['biceps_curl', 'hammer_curl', 'triceps_dip', 'triceps_extension', 'diamond_pushup', 'arm_circles']),
    ('shoulders', 'Shoulders', 'Плечи', 'open_with_rounded', 'male', 'intermediate', 'dumbbells', 35, 20, 3, 6,
     ['overhead_press', 'lateral_raise', 'front_raise', 'pike_pushup', 'shoulder_tap', 'shoulder_stretch']),
    ('back', 'Back', 'Спина', 'rowing_rounded', 'male', 'intermediate', 'none', 35, 20, 3, 7,
     ['superman', 'bird_dog', 'reverse_snow_angel', 'australian_pullup', 'dumbbell_row', 'good_morning']),
    ('legs', 'Legs', 'Ноги', 'directions_walk_rounded', 'male', 'intermediate', 'none', 40, 20, 3, 9,
     ['squat', 'bulgarian_split_squat', 'step_up', 'wall_sit', 'calf_raise', 'romanian_deadlift', 'jump_squat']),
    ('glutes_men', 'Glutes', 'Ягодицы', 'self_improvement_rounded', 'male', 'intermediate', 'none', 35, 15, 3, 7,
     ['hip_thrust', 'glute_bridge', 'romanian_deadlift', 'reverse_lunge', 'donkey_kick', 'single_leg_deadlift']),
    ('forearms', 'Forearms & grip', 'Предплечья и хват', 'pan_tool_rounded', 'male', 'beginner', 'dumbbells', 30, 15, 3, 4,
     ['wrist_curl', 'reverse_wrist_curl', 'dead_hang', 'farmer_carry']),
    ('neck', 'Neck', 'Шея', 'psychology_rounded', 'male', 'beginner', 'none', 25, 10, 2, 3,
     ['neck_tilt', 'neck_rotation', 'chin_tuck', 'neck_stretch']),
    ('fat_burn', 'Fat burn', 'Жиросжигание', 'whatshot_rounded', 'male', 'advanced', 'none', 30, 10, 3, 13,
     ['burpee', 'jumping_jack', 'mountain_climber', 'jump_squat', 'high_knees', 'squat_thrust', 'skater_jump', 'plank_jack', 'shadow_box']),
    ('dumbbells', 'With dumbbells', 'С гантелями', 'monitor_weight_rounded', 'male', 'intermediate', 'dumbbells', 40, 25, 3, 7,
     ['goblet_squat', 'dumbbell_row', 'overhead_press', 'biceps_curl', 'chest_fly_dumbbell', 'romanian_deadlift', 'lateral_raise']),
    ('barbell', 'With a barbell', 'Со штангой', 'monitor_weight_rounded', 'male', 'advanced', 'barbell', 45, 40, 4, 7,
     ['barbell_squat', 'bench_press_barbell', 'good_morning', 'romanian_deadlift', 'overhead_press']),
    ('pullup_bar', 'Pull-up bar', 'Турник', 'vertical_align_top_rounded', 'male', 'advanced', 'bar', 30, 40, 4, 8,
     ['pull_up', 'chin_up', 'australian_pullup', 'dead_hang']),
    ('dips_bars', 'Parallel bars', 'Брусья', 'unfold_more_rounded', 'male', 'advanced', 'bar', 30, 40, 4, 8,
     ['triceps_dip', 'pushup_hold', 'dead_hang', 'plank']),
    ('functional', 'Functional', 'Функциональная', 'sports_gymnastics_rounded', 'male', 'advanced', 'none', 35, 15, 3, 11,
     ['bear_crawl', 'crab_walk', 'farmer_carry', 'squat_thrust', 'bird_dog', 'skater_jump', 'plank_up_down']),

    # women
    ('glutes_w', 'Glutes', 'Ягодицы', 'self_improvement_rounded', 'female', 'beginner', 'none', 35, 15, 3, 7,
     ['glute_bridge', 'hip_thrust', 'donkey_kick', 'fire_hydrant', 'kickback', 'frog_pump', 'glute_bridge_march', 'clamshell']),
    ('legs_w', 'Legs', 'Ноги', 'directions_walk_rounded', 'female', 'beginner', 'none', 35, 15, 3, 8,
     ['sumo_squat', 'curtsy_lunge', 'reverse_lunge', 'wall_sit', 'calf_raise', 'single_leg_deadlift', 'step_up']),
    ('abs_w', 'Abs', 'Пресс', 'crop_square_rounded', 'female', 'beginner', 'none', 30, 12, 3, 7,
     ['dead_bug', 'crunches', 'bicycle', 'leg_raise', 'hollow_hold', 'v_up', 'plank', 'flutter_kicks']),
    ('waist', 'Waist', 'Талия', 'sync_alt_rounded', 'female', 'beginner', 'none', 30, 12, 3, 7,
     ['russian_twist', 'oblique_crunch', 'side_bend', 'side_plank', 'heel_taps', 'scissor_kick', 'torso_twist']),
    ('arms_w', 'Arms', 'Руки', 'front_hand_rounded', 'female', 'beginner', 'dumbbells', 30, 15, 3, 5,
     ['knee_pushup', 'triceps_dip', 'biceps_curl', 'lateral_raise', 'arm_circles', 'shoulder_stretch']),
    ('chest_w', 'Chest', 'Грудь', 'fitness_center_rounded', 'female', 'beginner', 'none', 30, 15, 3, 6,
     ['knee_pushup', 'incline_pushup', 'wide_pushup', 'chest_fly_dumbbell', 'chest_stretch']),
    ('pilates', 'Pilates', 'Пилатес', 'waves_rounded', 'female', 'beginner', 'none', 35, 10, 2, 5,
     ['pilates_hundred', 'pilates_roll_up', 'pilates_leg_circle', 'pilates_swimming', 'dead_bug', 'bridge_pose', 'side_plank']),
    ('yoga', 'Yoga', 'Йога', 'spa_rounded', 'female', 'beginner', 'none', 40, 8, 1, 4,
     ['downward_dog', 'warrior_two', 'tree_pose', 'bridge_pose', 'cobra_stretch', 'child_pose', 'cat_cow', 'seated_twist']),
    ('weight_loss', 'Weight loss', 'Похудение', 'favorite_rounded', 'female', 'intermediate', 'none', 30, 15, 3, 11,
     ['jumping_jack', 'squat', 'mountain_climber', 'high_knees', 'glute_bridge', 'plank', 'skater_jump', 'side_shuffle']),
    ('posture', 'Posture', 'Осанка', 'straighten_rounded', 'female', 'beginner', 'none', 30, 10, 2, 4,
     ['chin_tuck', 'reverse_snow_angel', 'bird_dog', 'superman', 'chest_stretch', 'cat_cow', 'shoulder_roll']),
]


def camel(s):
    parts = s.split('_')
    return parts[0] + ''.join(p.capitalize() for p in parts[1:])


def cap(s):
    c = camel(s)
    return c[0].upper() + c[1:]


def dq(s):
    """A Dart single-quoted string literal."""
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def main():
    ids = [e[0] for e in EX]
    assert len(ids) == len(set(ids)), 'duplicate exercise id'
    known = set(ids)
    for r in ROUTINES:
        for x in r[11]:
            assert x in known, 'routine %s references unknown exercise %s' % (r[0], x)

    out = ["""import 'package:flutter/material.dart';

// GENERATED by tool/fitgen.py — edit the spec there and re-run, don't hand-edit.
// The Dart table and both l10n dictionaries come out of one spec, which is what
// makes a missing translation impossible rather than merely unlikely.

/// Which built-in motion loop (see lib/widgets/exercise_motion.dart) plays
/// behind an exercise's icon — a lightweight, zero-asset stand-in for a real
/// form-demo GIF/video (deliberately not that: no external hosting/CDN, see
/// the architecture note in exercise_motion.dart).
enum ExerciseMotion { squat, pushup, lunge, plank, jump, core }

/// Who a routine is aimed at. `both` appears under either tab instead of being
/// duplicated per gender — a squat is a squat.
enum FitGender { male, female, both }

enum FitLevel { beginner, intermediate, advanced }

/// What you need to hand. Drives the equipment chip and the
/// "no equipment only" filter.
enum FitEquipment { none, dumbbells, barbell, bar }

/// One exercise: name + short technique cue read aloud by the on-device TTS
/// coach, both stored as l10n KEYS (not literal text) so the exercise DB
/// follows the app's language setting — resolve with `context.t(nameKey)` /
/// `context.t(cueKey)` at the point of use.
class FitExercise {
  final String id;
  final String nameKey;
  final String cueKey;
  final IconData icon;
  final ExerciseMotion motion;
  const FitExercise(this.id, this.nameKey, this.cueKey, this.icon, this.motion);
}

/// A timed circuit: work/rest seconds apply to every exercise in it, and the
/// whole circuit repeats [sets] times.
///
/// Duration, exercise count and calories are all COMPUTED from these numbers
/// rather than stored as text, so a card can never drift out of sync with the
/// workout it describes.
class FitRoutine {
  final String id;
  final String titleKey;
  final IconData icon;
  final int workSec;
  final int restSec;
  final int sets;
  final FitGender gender;
  final FitLevel level;
  final FitEquipment equipment;

  /// Rough intensity for the calorie estimate. Per-minute on purpose: a stored
  /// total would stop matching as soon as [sets] changed.
  final int kcalPerMin;

  final List<FitExercise> exercises;

  const FitRoutine(
    this.id,
    this.titleKey,
    this.icon,
    this.workSec,
    this.restSec, {
    this.sets = 1,
    this.gender = FitGender.both,
    this.level = FitLevel.beginner,
    this.equipment = FitEquipment.none,
    this.kcalPerMin = 6,
    required this.exercises,
  });

  int get estimatedMinutes =>
      (((workSec + restSec) * exercises.length * sets) / 60)
          .round()
          .clamp(1, 999);

  int get estimatedKcal => estimatedMinutes * kcalPerMin;

  String get levelKey => 'fitLevel_${level.name}';
  String get equipmentKey => 'fitEquip_${equipment.name}';

  bool matchesGender(FitGender tab) =>
      gender == FitGender.both || gender == tab;
}
"""]

    out.append('// ─── Exercise library ───────────────────────────────────────────────────────')
    for (eid, en, ru, ecue, rcue, icon, motion) in EX:
        out.append("const _%s = FitExercise('%s', 'ex%sName', 'ex%sCue',\n    Icons.%s, ExerciseMotion.%s);"
                   % (camel(eid), eid, cap(eid), cap(eid), icon, motion))

    out.append('\n// ─── Routines ──────────────────────────────────────────────────────────────')
    out.append('const List<FitRoutine> kFitRoutines = [')
    for (rid, en, ru, icon, gender, level, equip, work, rest, sets, kcal, exids) in ROUTINES:
        ex_list = ', '.join('_' + camel(x) for x in exids)
        out.append(
            "  FitRoutine(\n    '%s',\n    'fit%sTitle',\n    Icons.%s,\n    %d, %d,\n"
            "    sets: %d,\n    gender: FitGender.%s,\n    level: FitLevel.%s,\n"
            "    equipment: FitEquipment.%s,\n    kcalPerMin: %d,\n    exercises: [%s],\n  ),"
            % (rid, cap(rid), icon, work, rest, sets, gender, level, equip, kcal, ex_list))
    out.append('];')

    io.open('lib/data/exercises_data.dart', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('exercises_data.dart: %d exercises, %d routines' % (len(EX), len(ROUTINES)))

    # ── l10n ──
    p = 'lib/l10n/app_strings.dart'
    s = io.open(p, encoding='utf-8').read()

    def have(key):
        return ("'%s':" % key) in s

    en_lines, ru_lines = [], []
    for (eid, en, ru, ecue, rcue, icon, motion) in EX:
        kn, kc = 'ex%sName' % cap(eid), 'ex%sCue' % cap(eid)
        if not have(kn):
            en_lines.append("      '%s': %s," % (kn, dq(en)))
            ru_lines.append("      '%s': %s," % (kn, dq(ru)))
        if not have(kc):
            en_lines.append("      '%s': %s," % (kc, dq(ecue)))
            ru_lines.append("      '%s': %s," % (kc, dq(rcue)))
    for r in ROUTINES:
        k = 'fit%sTitle' % cap(r[0])
        if not have(k):
            en_lines.append("      '%s': %s," % (k, dq(r[1])))
            ru_lines.append("      '%s': %s," % (k, dq(r[2])))

    extra = [
        ('fitLevel_beginner', 'Beginner', 'Новичок'),
        ('fitLevel_intermediate', 'Intermediate', 'Средний'),
        ('fitLevel_advanced', 'Advanced', 'Продвинутый'),
        ('fitEquip_none', 'No equipment', 'Без оборудования'),
        ('fitEquip_dumbbells', 'Dumbbells', 'Гантели'),
        ('fitEquip_barbell', 'Barbell', 'Штанга'),
        ('fitEquip_bar', 'Bar / dip bars', 'Турник / брусья'),
        ('fitTabMen', 'Men', 'Мужчинам'),
        ('fitTabWomen', 'Women', 'Женщинам'),
        ('fitNoEquipOnly', 'No equipment', 'Без оборудования'),
        ('fitSetsLabel', '{n} sets', 'Подходов: {n}'),
        ('fitKcalLabel', '~{n} kcal', '~{n} ккал'),
        ('fitNothingFound', 'Nothing matches this filter', 'По этому фильтру ничего нет'),
        ('fitHistoryTitle', 'Workout history', 'История занятий'),
        ('fitHistoryEmpty', 'No workouts yet', 'Пока нет тренировок'),
        ('fitTotalWorkouts', 'Workouts: {n}', 'Тренировок: {n}'),
        ('fitStreakLabel', 'Streak: {n} d', 'Серия: {n} дн.'),
    ]
    for (k, en, ru) in extra:
        if not have(k):
            en_lines.append("      '%s': %s," % (k, dq(en)))
            ru_lines.append("      '%s': %s," % (k, dq(ru)))

    a_en = "      'photoLabel': 'Photo',"
    a_ru = "      'photoLabel': 'Фото',"
    assert a_en in s and a_ru in s
    s = s.replace(a_en, '\n'.join(en_lines) + '\n' + a_en, 1)
    s = s.replace(a_ru, '\n'.join(ru_lines) + '\n' + a_ru, 1)
    io.open(p, 'w', encoding='utf-8').write(s)
    print('l10n: added %d en / %d ru lines' % (len(en_lines), len(ru_lines)))


if __name__ == '__main__':
    main()
