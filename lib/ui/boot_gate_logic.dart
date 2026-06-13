/// Faut-il encore afficher le boot ? On quitte quand l'init est résolue ET
/// (la durée minimale est écoulée OU l'utilisateur a tapé pour passer).
bool shouldShowBoot({
  required bool minElapsed,
  required bool skipRequested,
  required bool initResolved,
}) =>
    !(initResolved && (minElapsed || skipRequested));
