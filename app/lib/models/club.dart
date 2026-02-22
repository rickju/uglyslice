enum ClubType {
  iron,
  wood,
  hybrid,
  putter,
  driver,
}

class Club {
  final String name;
  final String brand;
  final String number;
  final ClubType type;
  final double loft;

  Club({
    required this.name,
    required this.brand,
    required this.number,
    required this.type,
    this.loft = 0.0,
  });
}
