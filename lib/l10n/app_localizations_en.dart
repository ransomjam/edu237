// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Camiva';

  @override
  String get navHome => 'Home';

  @override
  String get navChildren => 'Children';

  @override
  String get navPayments => 'Payments';

  @override
  String get navEarnings => 'Earnings';

  @override
  String get navProfile => 'Profile';

  @override
  String get homeTitle => 'Home';

  @override
  String get profileTitle => 'Profile';

  @override
  String get placeholderHome => 'Your activity will appear here.';

  @override
  String get parentHomeWelcome => 'Welcome';

  @override
  String get parentHomeEmptyBody => 'Add your child to get started.';

  @override
  String get addChildButton => 'Add your child';

  @override
  String get childrenTitle => 'Children';

  @override
  String get childNoTeacher => 'No teacher yet';

  @override
  String get childTeacherConnected => 'Teacher connected';

  @override
  String get findTeacherButton => 'Find a teacher';

  @override
  String get findTeacherComingSoon => 'Finding a teacher is coming soon.';

  @override
  String get addChildTitle => 'Add your child';

  @override
  String get addChildNameLabel => 'Child\'s name';

  @override
  String get addChildLevelLabel => 'School level or class';

  @override
  String get addChildNotesLabel => 'Notes (optional)';

  @override
  String get addChildSave => 'Save';

  @override
  String addChildStepLabel(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get addChildStepName => 'What is your child\'s name?';

  @override
  String get addChildStepClass => 'What class is your child in?';

  @override
  String get addChildSubjectsLower => 'What subjects does your child take?';

  @override
  String get addChildSubjectsUpper => 'What subjects is your child taking?';

  @override
  String get addChildContinue => 'Continue';

  @override
  String get addChildBack => 'Back';

  @override
  String get addChildSaveChild => 'Save Child';

  @override
  String get addChildSelectClassError => 'Please choose a class to continue.';

  @override
  String childSubjectCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subjects',
      one: '1 subject',
      zero: 'No subjects yet',
    );
    return '$_temp0';
  }

  @override
  String get childDetailEdit => 'Edit child';

  @override
  String get childDetailClassLabel => 'Class';

  @override
  String get childDetailSubjectsLabel => 'Subjects';

  @override
  String get childDetailNotesLabel => 'Notes';

  @override
  String get childDetailNoSubjects => 'No subjects added yet.';

  @override
  String get childDetailNotSet => 'Not set';

  @override
  String get editChildTitle => 'Edit child';

  @override
  String get editChildNameQuestion => 'Child\'s name';

  @override
  String get editChildClassQuestion => 'Class';

  @override
  String get editChildSave => 'Save changes';

  @override
  String get childrenLoading => 'Loading…';

  @override
  String get childrenLoadError =>
      'Could not load your children. Please try again.';

  @override
  String get teacherHomePlaceholder => 'Your teaching space is coming soon.';

  @override
  String get teacherProfileTitle => 'My profile';

  @override
  String get teacherNoProfileTitle => 'Set up your teaching profile';

  @override
  String get teacherNoProfileBody =>
      'Add your subjects and classes so parents can find you.';

  @override
  String get teacherCreateProfile => 'Create profile';

  @override
  String get teacherEditProfile => 'Edit profile';

  @override
  String get teacherEditTitle => 'Edit profile';

  @override
  String get teacherNameLabel => 'Your name';

  @override
  String get teacherNameSection => 'Your name';

  @override
  String get teacherSubjectsQuestion => 'What subjects do you teach?';

  @override
  String get teacherFormsQuestion => 'Which classes do you teach?';

  @override
  String get teacherBioLabel => 'Short bio (optional)';

  @override
  String get teacherBioSection => 'About';

  @override
  String get teacherProfileSubjectsLabel => 'Subjects';

  @override
  String get teacherProfileFormsLabel => 'Classes';

  @override
  String get teacherSaveProfile => 'Save profile';

  @override
  String get childDetailFindTeacher => 'Find a teacher';

  @override
  String get discoveryTitle => 'Find a teacher';

  @override
  String discoveryForChild(String name) {
    return 'Teachers for $name';
  }

  @override
  String get discoveryEmptyTitle => 'No teachers found';

  @override
  String discoveryEmptyBody(String name) {
    return 'We couldn\'t find a matching teacher for $name yet. Please check back soon.';
  }

  @override
  String teacherRequestButton(String name) {
    return 'Request to teach $name';
  }

  @override
  String get teacherRequestComingSoon => 'Requesting a teacher is coming next.';

  @override
  String get teacherRequestComingSoonCaption => 'Coming next';

  @override
  String get teacherProfileNoBio => 'No bio yet.';

  @override
  String get placeholderProfile => 'Your profile will appear here.';

  @override
  String get roleParent => 'Parent';

  @override
  String get roleTeacher => 'Teacher';

  @override
  String get roleStudent => 'Student';

  @override
  String get roleChoiceParent => 'I am a Parent';

  @override
  String get roleChoiceParentHint =>
      'Manage your children and find teachers for them.';

  @override
  String get roleChoiceTeacher => 'I am a Teacher';

  @override
  String get roleChoiceTeacherHint =>
      'Share what you teach and connect with families.';

  @override
  String get roleChoiceStudent => 'I am a Student';

  @override
  String get roleChoiceStudentHint =>
      'See your subjects, teachers and lessons.';

  @override
  String get navLearning => 'Learning';

  @override
  String studentHomeGreeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get studentProfileTitle => 'My profile';

  @override
  String get studentSetupTitle => 'Your school details';

  @override
  String get devRoleSwitchLabel => 'Switch role (dev only)';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitle => 'Welcome back to Camiva.';

  @override
  String get loginButton => 'Sign in';

  @override
  String get loginNoAccount => 'Don\'t have an account?';

  @override
  String get loginRegisterLink => 'Register';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerSubtitle => 'Join Camiva.';

  @override
  String get registerButton => 'Create account';

  @override
  String get registerHaveAccount => 'Already have an account?';

  @override
  String get registerLoginLink => 'Sign in';

  @override
  String get registerRoleLabel => 'Tell us who you are';

  @override
  String get registerRolePrompt => 'Please choose how you will use Camiva.';

  @override
  String get registerEmailConfirmation =>
      'Check your email to confirm your account, then sign in.';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldConfirmPassword => 'Confirm password';

  @override
  String get fieldName => 'Full name';

  @override
  String get validationRequired => 'This field is required.';

  @override
  String get validationEmailInvalid => 'Enter a valid email address.';

  @override
  String get validationPasswordTooShort =>
      'Password must be at least 6 characters.';

  @override
  String get validationPasswordMismatch => 'Passwords do not match.';

  @override
  String get profileName => 'Name';

  @override
  String get profileEmail => 'Email';

  @override
  String get profileRole => 'Role';

  @override
  String get profileLogout => 'Log out';

  @override
  String get profileLogoutConfirmTitle => 'Log out?';

  @override
  String get profileLogoutConfirmBody =>
      'You will need to sign in again to access your account.';

  @override
  String get profileLogoutConfirm => 'Log out';

  @override
  String get profileLogoutCancel => 'Cancel';

  @override
  String get errorBackendNotConfigured =>
      'The app is not connected to a backend. Please contact support.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get onboardingTitle => 'How will you use Camiva?';

  @override
  String get onboardingSubtitle =>
      'Choose your role. You can update this later.';

  @override
  String get onboardingNameLabel => 'Your name';

  @override
  String get onboardingRoleLabel => 'I am a';

  @override
  String get onboardingButton => 'Continue';

  @override
  String get onboardingErrorNetwork =>
      'No connection. Please check your internet and try again.';

  @override
  String get loadingProfile => 'Loading your profile…';

  @override
  String get errorProfileLoad =>
      'Could not load your profile. Please check your connection.';

  @override
  String get retryButton => 'Retry';

  @override
  String get requestSent => 'Request sent';

  @override
  String get requestPending => 'Request pending';

  @override
  String get requestAccepted => 'Teacher connected';

  @override
  String get requestDeclined => 'Request declined';

  @override
  String get requestCancelled => 'Request cancelled';

  @override
  String get requestCancelButton => 'Cancel request';

  @override
  String get requestAlreadySent =>
      'A request has already been sent for this child and teacher.';

  @override
  String get parentRequestsTitle => 'My Requests';

  @override
  String get parentRequestsEmpty => 'You have no requests yet.';

  @override
  String get teacherRequestsTitle => 'Teaching Requests';

  @override
  String get teacherRequestsEmpty => 'No incoming requests.';

  @override
  String get requestAcceptButton => 'Accept';

  @override
  String get requestDeclineButton => 'Decline';

  @override
  String get myStudentsTitle => 'My Students';

  @override
  String get myStudentsEmpty => 'You have no connected students yet.';

  @override
  String get studentConnectedTeacherLabel => 'Teacher';

  @override
  String get studentNoTeacherYet => 'No teacher connected yet.';

  @override
  String get requestChildLabel => 'Child';

  @override
  String get requestTeacherLabel => 'Teacher';

  @override
  String get requestStatusLabel => 'Status';

  @override
  String get navRequests => 'Updates';

  @override
  String get teacherHomeRequests => 'Teaching Requests';

  @override
  String get teacherHomeStudents => 'My Students';

  @override
  String get studentFormLabel => 'Class';

  @override
  String get connectedBadge => 'Connected';

  @override
  String requestForChild(String name) {
    return 'For $name';
  }

  @override
  String get teacherLocationSection => 'Location';

  @override
  String get teacherLocationHint =>
      'Roughly where you teach. Parents see your area, never your exact address.';

  @override
  String get teacherCityLabel => 'City / town';

  @override
  String get teacherAreaLabel => 'Neighbourhood / area (optional)';

  @override
  String get teacherProfileLocationLabel => 'Location';

  @override
  String requestParentOf(String name) {
    return 'Parent of $name';
  }

  @override
  String get requestMatchesYourSubjects => 'Matches your subjects';

  @override
  String requestRequestedOn(String date) {
    return 'Requested $date';
  }

  @override
  String get requestChildUnavailable => 'Child details unavailable';

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get errorGenericBody => 'Please try again.';

  @override
  String get childrenEmptyTitle => 'Add your first child';

  @override
  String get childrenEmptyBody =>
      'Add their Form and subjects to start finding teachers.';

  @override
  String get parentHomeChildrenSection => 'Your children';

  @override
  String get parentHomeAttentionSection => 'Needs your attention';

  @override
  String get parentHomeLearningSection => 'Recent learning';

  @override
  String get homeQuickActions => 'Quick actions';

  @override
  String childSummary(String form, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subjects',
      one: '1 subject',
    );
    return '$form · $_temp0';
  }

  @override
  String attentionActivityDue(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activities',
      one: '1 activity',
    );
    return '$name has $_temp0 due soon.';
  }

  @override
  String attentionPendingRequest(String name) {
    return '$name has a pending teacher request.';
  }

  @override
  String get requestsNeedsResponse => 'Needs your response';

  @override
  String get requestsConnectedSection => 'Connected';

  @override
  String get requestsPendingSection => 'Pending';

  @override
  String get requestsHistorySection => 'Earlier';

  @override
  String get teacherRequestsEmptyTitle => 'No requests yet';

  @override
  String get teacherRequestsEmptyBody =>
      'Requests from parents will appear here.';

  @override
  String get parentRequestsEmptyTitle => 'No requests yet';

  @override
  String get parentRequestsEmptyBody =>
      'Teachers you request will appear here.';

  @override
  String get myStudentsEmptyTitle => 'No students yet';

  @override
  String get myStudentsEmptyBody =>
      'Accepted teacher connections will appear here.';

  @override
  String get teacherHomeTodaySection => 'Today';

  @override
  String get teacherHomePendingSection => 'Pending';

  @override
  String get teacherHomeStudentsSection => 'My students';

  @override
  String teacherHomeLearningToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count learning activities',
      one: '1 learning activity',
      zero: 'No activities today',
    );
    return '$_temp0';
  }

  @override
  String teacherHomeNeedsAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count students need attention',
      one: '1 student needs attention',
    );
    return '$_temp0';
  }

  @override
  String teacherHomePendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count teaching requests',
      one: '1 teaching request',
    );
    return '$_temp0';
  }

  @override
  String get teacherHomeViewStudents => 'View students';

  @override
  String get teacherHomeViewRequests => 'View requests';

  @override
  String get teacherHomeCreateActivity => 'Create learning activity';

  @override
  String teacherWhyMatch(String name) {
    return 'Why $name may be a good match';
  }

  @override
  String teacherMatchForm(String form) {
    return 'Teaches $form';
  }

  @override
  String teacherMatchSubject(String subject) {
    return 'Teaches $subject';
  }

  @override
  String get learningEmptyParentTitle => 'No learning updates yet';

  @override
  String get learningEmptyParentBody =>
      'Updates from your child\'s teachers will appear here.';

  @override
  String get findTeacherAction => 'Find a teacher';

  @override
  String get teacherHomeSubtitle => 'Your teaching workspace';

  @override
  String discoveryHeaderTitle(String name) {
    return 'Find a teacher for $name';
  }

  @override
  String get discoveryViewMap => 'Map';

  @override
  String get discoveryViewList => 'List';

  @override
  String get discoveryNearby => 'Nearby';

  @override
  String get discoveryOnline => 'Online';

  @override
  String get discoveryFilterSubject => 'Subject';

  @override
  String get discoveryFilterForm => 'Form';

  @override
  String get discoveryFilterAllSubjects => 'All subjects';

  @override
  String get discoveryFilterAllForms => 'All forms';

  @override
  String get discoveryClearFilters => 'Clear';

  @override
  String get discoveryNearYou => 'Teachers near you';

  @override
  String discoveryInCity(String city) {
    return 'Teachers in $city';
  }

  @override
  String get discoveryRelevantTeachers => 'Relevant teachers';

  @override
  String discoveryResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count teachers',
      one: '1 teacher',
    );
    return '$_temp0';
  }

  @override
  String get discoveryBestMatch => 'Best match';

  @override
  String get discoveryLocating => 'Finding teachers near you…';

  @override
  String get discoveryUseMyLocation => 'Use my location';

  @override
  String get discoveryEmptyNearbyTitle => 'No teachers found nearby';

  @override
  String get discoveryEmptyNearbyBody =>
      'Try another subject, Form, or view all teachers.';

  @override
  String get discoveryViewAll => 'View all teachers';

  @override
  String get discoveryLocationUnavailableTitle => 'Location isn\'t available';

  @override
  String get discoveryLocationUnavailableBody =>
      'You can still browse teachers in your area.';

  @override
  String get discoveryMapUnavailableTitle => 'Map couldn\'t load';

  @override
  String get discoveryMapUnavailableBody =>
      'Browse teachers in the list instead.';

  @override
  String get discoveryNoMapForTeacher => 'Approximate area only';

  @override
  String get discoveryMapAttributionOsm => '© OpenStreetMap';

  @override
  String get teacherServiceAreaNote => 'Teaching area — not a home address.';

  @override
  String get teacherTeachingModeLabel => 'Teaching mode';

  @override
  String get teacherTeachingModeOnline => 'Online';

  @override
  String get teacherTeachingModeInPerson => 'In person';

  @override
  String get teacherTeachingModeBoth => 'Online + In person';

  @override
  String get teacherModeQuestion => 'How do you teach?';

  @override
  String get teacherModeHint =>
      'Parents will see whether you can teach in person, online, or both.';

  @override
  String get teacherPinAreaTitle => 'Approximate map location (optional)';

  @override
  String get teacherPinAreaHint =>
      'Add a rough pin so parents can see your area on the map. We round it so it never shows your exact address.';

  @override
  String get teacherPinAreaButton => 'Use my current area';

  @override
  String get teacherPinAreaSet => 'Approximate area set';

  @override
  String get teacherPinAreaClear => 'Remove pin';

  @override
  String get teacherPinAreaDenied =>
      'Location permission is off. You can still enter your city and area above.';

  @override
  String teacherWhyMatchFor(String teacherName, String childName) {
    return 'Why $teacherName is a good match for $childName';
  }

  @override
  String teacherMatchArea(String area) {
    return 'Covers $area';
  }

  @override
  String get profilePhotoChange => 'Change photo';

  @override
  String get profilePhotoRemove => 'Remove photo';

  @override
  String get profilePhotoUpload => 'Add photo';

  @override
  String get profilePhotoUploading => 'Uploading photo…';

  @override
  String get profilePhotoError => 'Could not update photo. Please try again.';

  @override
  String get profilePhotoRemoved => 'Photo removed';

  @override
  String get profilePhotoUpdated => 'Photo updated';

  @override
  String get homeTutorLabel => 'Home Tutor';

  @override
  String get homeTutoringSection => 'Home tutoring';

  @override
  String get homeTutoringBadge => 'In-home tutoring';

  @override
  String get teacherAreasSection => 'Teaching areas';

  @override
  String get reviewsSection => 'Reviews';

  @override
  String get reviewsEmptyTitle => 'No reviews yet';

  @override
  String get qualificationsSection => 'Qualifications';

  @override
  String get qualificationsEmpty => 'Not listed yet.';

  @override
  String get experienceSection => 'Experience';

  @override
  String get profileAccountSection => 'Account';

  @override
  String get profileEditAvailability => 'Edit availability';

  @override
  String get requestThisTeacher => 'Request this teacher';

  @override
  String get availabilitySection => 'Availability';

  @override
  String get fieldPhone => 'Phone number';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldPinConfirm => 'Confirm PIN';

  @override
  String get validationPhoneInvalid =>
      'Enter a valid number, e.g. 670 00 00 00.';

  @override
  String get validationPinInvalid => 'Your PIN must be 4 to 6 digits.';

  @override
  String get validationPinMismatch => 'The two PINs do not match.';

  @override
  String get pinHelper => 'Choose 4 to 6 digits you will remember.';
}
