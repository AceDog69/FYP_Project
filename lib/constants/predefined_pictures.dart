/// Stable stored IDs. Supplied filenames are preserved exactly.
const predefinedPictures = <String, String>{
  'bento': 'Bento.png',
  'bibimbap': 'Bibimbap.png',
  'burger': 'Burger.png',
  'cake': 'Cake.png',
  'chinese_food_1': 'Chinese_Food_1.png',
  'chinese_food_2': 'Chinese_Food_2.png',
  'chinese_food_3': 'Chinese_Food_3.png',
  'chinese_food_4': 'Chinese_Food_4.png',
  'coffee': 'Coffee.png',
  'dessert': 'Dessert.png',
  'drink': 'Drink.png',
  'fruit_juice': 'Fruit_Juice.png',
  'icecream': 'Icecream.png',
  'japanese_1': 'Japanese 1.png',
  'japanese_curry': 'Japanese_Curry.png',
  'korean_ramen': 'Korean_Ramen.png',
  'malay_drinks': 'Malay_Drinks.png',
  'malay_food': 'Malay_Food.png',
  'nasi_lemak': 'Nasi_Lemak.png',
  'sushi': 'Sushi.png',
  'teh_ais': 'Teh_Ais.png',
  'tteokbokki': 'Tteokbokki.png',
  'western_food': 'Western_Food.png',
};

String defaultStallPicture(String category) => switch (category) {
  'Western' => 'western_food',
  'Chinese' => 'chinese_food_1',
  'Japanese' => 'bento',
  'Korean' => 'bibimbap',
  'Beverage' => 'drink',
  'Dessert' => 'dessert',
  _ => 'nasi_lemak',
};

String resolvedPictureId(String? id, String category) =>
    predefinedPictures.containsKey(id) ? id! : defaultStallPicture(category);

String pictureAsset(String id) =>
    'assets/predefined_pictures/${predefinedPictures[id]!}';

String pictureLabel(String id) =>
    predefinedPictures[id]!.replaceFirst('.png', '').replaceAll('_', ' ');
