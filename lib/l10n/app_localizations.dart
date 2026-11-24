import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The name of the application
  ///
  /// In en, this message translates to:
  /// **'Camiva'**
  String get appName;

  /// Bottom navigation label for the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label for the Children tab
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get navChildren;

  /// Bottom navigation label for the Payments tab (parent)
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get navPayments;

  /// Bottom navigation label for the Earnings tab (teacher)
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get navEarnings;

  /// Bottom navigation label for the Profile tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// AppBar title for the Home screen
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// AppBar title for the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Placeholder text on the Home screen
  ///
  /// In en, this message translates to:
  /// **'Your activity will appear here.'**
  String get placeholderHome;

  /// Greeting on the parent home when there are no children yet
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get parentHomeWelcome;

  /// Guidance shown to a parent with no children
  ///
  /// In en, this message translates to:
  /// **'Add your child to get started.'**
  String get parentHomeEmptyBody;

  /// Primary button to add a child
  ///
  /// In en, this message translates to:
  /// **'Add your child'**
  String get addChildButton;

  /// Title for the Children screen
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get childrenTitle;

  /// Shown on a child card when no teacher is linked
  ///
  /// In en, this message translates to:
  /// **'No teacher yet'**
  String get childNoTeacher;

  /// Shown on a child card when a teacher relationship is accepted
  ///
  /// In en, this message translates to:
  /// **'Teacher connected'**
  String get childTeacherConnected;

  /// Button to start finding a teacher for a child
  ///
  /// In en, this message translates to:
  /// **'Find a teacher'**
  String get findTeacherButton;

  /// Temporary message until teacher search is built
  ///
  /// In en, this message translates to:
  /// **'Finding a teacher is coming soon.'**
  String get findTeacherComingSoon;

  /// Title for the add-child screen
  ///
  /// In en, this message translates to:
  /// **'Add your child'**
  String get addChildTitle;

  /// Label for the child's name field
  ///
  /// In en, this message translates to:
  /// **'Child\'s name'**
  String get addChildNameLabel;

  /// Label for the child's school level field
  ///
  /// In en, this message translates to:
  /// **'School level or class'**
  String get addChildLevelLabel;

  /// Label for the optional notes field
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get addChildNotesLabel;

  /// Save button on the add-child screen
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get addChildSave;

  /// Progress label on the add-child steps
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String addChildStepLabel(int current, int total);

  /// Step 1 question: child's name
  ///
  /// In en, this message translates to:
  /// **'What is your child\'s name?'**
  String get addChildStepName;

  /// Step 2 question: child's class
  ///
  /// In en, this message translates to:
  /// **'What class is your child in?'**
  String get addChildStepClass;

  /// Step 3 question for Forms 1-3
  ///
  /// In en, this message translates to:
  /// **'What subjects does your child take?'**
  String get addChildSubjectsLower;

  /// Step 3 question for Forms 4-5
  ///
  /// In en, this message translates to:
  /// **'What subjects is your child taking?'**
  String get addChildSubjectsUpper;

  /// Advance to the next add-child step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get addChildContinue;

  /// Go to the previous add-child step
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get addChildBack;

  /// Final save button on the add-child flow
  ///
  /// In en, this message translates to:
  /// **'Save Child'**
  String get addChildSaveChild;

  /// Shown when no class is selected
  ///
  /// In en, this message translates to:
  /// **'Please choose a class to continue.'**
  String get addChildSelectClassError;

  /// Subject count on the child card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No subjects yet} =1{1 subject} other{{count} subjects}}'**
  String childSubjectCount(int count);

  /// Button to edit a child from the detail screen
  ///
  /// In en, this message translates to:
  /// **'Edit child'**
  String get childDetailEdit;

  /// Label for the child's class on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get childDetailClassLabel;

  /// Label for the subjects section on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Subjects'**
  String get childDetailSubjectsLabel;

  /// Label for the notes section on the detail screen
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get childDetailNotesLabel;

  /// Shown when a child has no subjects
  ///
  /// In en, this message translates to:
  /// **'No subjects added yet.'**
  String get childDetailNoSubjects;

  /// Shown when the class is not set
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get childDetailNotSet;

  /// Title of the edit-child screen
  ///
  /// In en, this message translates to:
  /// **'Edit child'**
  String get editChildTitle;

  /// Name section header on the edit screen
  ///
  /// In en, this message translates to:
  /// **'Child\'s name'**
  String get editChildNameQuestion;

  /// Class section header on the edit screen
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get editChildClassQuestion;

  /// Save button on the edit-child screen
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get editChildSave;

  /// Loading message on the children/home screens
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get childrenLoading;

  /// Error shown when children fail to load
  ///
  /// In en, this message translates to:
  /// **'Could not load your children. Please try again.'**
  String get childrenLoadError;

  /// Placeholder on the teacher home before Slice 2
  ///
  /// In en, this message translates to:
  /// **'Your teaching space is coming soon.'**
  String get teacherHomePlaceholder;

  /// Title of the teacher's own profile
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get teacherProfileTitle;

  /// Prompt when a teacher has no profile yet
  ///
  /// In en, this message translates to:
  /// **'Set up your teaching profile'**
  String get teacherNoProfileTitle;

  /// Body of the no-profile prompt
  ///
  /// In en, this message translates to:
  /// **'Add your subjects and classes so parents can find you.'**
  String get teacherNoProfileBody;

  /// Button to create a teacher profile
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get teacherCreateProfile;

  /// Button to edit a teacher profile
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get teacherEditProfile;

  /// Title of the teacher profile edit screen
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get teacherEditTitle;

  /// Label for the teacher's display name
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get teacherNameLabel;

  /// Section header for the teacher name
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get teacherNameSection;

  /// Section header for teacher subjects
  ///
  /// In en, this message translates to:
  /// **'What subjects do you teach?'**
  String get teacherSubjectsQuestion;

  /// Section header for teacher forms
  ///
  /// In en, this message translates to:
  /// **'Which classes do you teach?'**
  String get teacherFormsQuestion;

  /// Label for the teacher bio field
  ///
  /// In en, this message translates to:
  /// **'Short bio (optional)'**
  String get teacherBioLabel;

  /// Section header for the teacher bio
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get teacherBioSection;

  /// Label for subjects on a teacher profile
  ///
  /// In en, this message translates to:
  /// **'Subjects'**
  String get teacherProfileSubjectsLabel;

  /// Label for forms/classes on a teacher profile
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get teacherProfileFormsLabel;

  /// Save button on the teacher edit screen
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get teacherSaveProfile;

  /// Primary action on child detail to open discovery
  ///
  /// In en, this message translates to:
  /// **'Find a teacher'**
  String get childDetailFindTeacher;

  /// Title of the teacher discovery screen
  ///
  /// In en, this message translates to:
  /// **'Find a teacher'**
  String get discoveryTitle;

  /// Subtitle showing which child discovery is for
  ///
  /// In en, this message translates to:
  /// **'Teachers for {name}'**
  String discoveryForChild(String name);

  /// Title when discovery has no matches
  ///
  /// In en, this message translates to:
  /// **'No teachers found'**
  String get discoveryEmptyTitle;

  /// Body when discovery has no matches
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a matching teacher for {name} yet. Please check back soon.'**
  String discoveryEmptyBody(String name);

  /// Primary action on a teacher profile (deferred)
  ///
  /// In en, this message translates to:
  /// **'Request to teach {name}'**
  String teacherRequestButton(String name);

  /// Shown when the deferred request button is tapped
  ///
  /// In en, this message translates to:
  /// **'Requesting a teacher is coming next.'**
  String get teacherRequestComingSoon;

  /// Caption under the deferred request button
  ///
  /// In en, this message translates to:
  /// **'Coming next'**
  String get teacherRequestComingSoonCaption;

  /// Shown when a teacher has no bio
  ///
  /// In en, this message translates to:
  /// **'No bio yet.'**
  String get teacherProfileNoBio;

  /// Placeholder text on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Your profile will appear here.'**
  String get placeholderProfile;

  /// Label for the Parent role
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get roleParent;

  /// Label for the Teacher role
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get roleTeacher;

  /// Label for the Student role
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get roleStudent;

  /// Friendly Parent option on the role chooser
  ///
  /// In en, this message translates to:
  /// **'I am a Parent'**
  String get roleChoiceParent;

  /// Supporting text for the Parent role option
  ///
  /// In en, this message translates to:
  /// **'Manage your children and find teachers for them.'**
  String get roleChoiceParentHint;

  /// Friendly Teacher option on the role chooser
  ///
  /// In en, this message translates to:
  /// **'I am a Teacher'**
  String get roleChoiceTeacher;

  /// Supporting text for the Teacher role option
  ///
  /// In en, this message translates to:
  /// **'Share what you teach and connect with families.'**
  String get roleChoiceTeacherHint;

  /// Friendly Student option on the role chooser
  ///
  /// In en, this message translates to:
  /// **'I am a Student'**
  String get roleChoiceStudent;

  /// Supporting text for the Student role option
  ///
  /// In en, this message translates to:
  /// **'See your subjects, teachers and lessons.'**
  String get roleChoiceStudentHint;

  /// Bottom navigation label for the student Learning tab
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get navLearning;

  /// Greeting on the student home screen
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String studentHomeGreeting(String name);

  /// Title of the student profile screen
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get studentProfileTitle;

  /// Heading above the education questions during student signup
  ///
  /// In en, this message translates to:
  /// **'Your school details'**
  String get studentSetupTitle;

  /// Label for the dev-only role switcher
  ///
  /// In en, this message translates to:
  /// **'Switch role (dev only)'**
  String get devRoleSwitchLabel;

  /// Title for the Login screen
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginTitle;

  /// Subtitle shown on the Login screen
  ///
  /// In en, this message translates to:
  /// **'Welcome back to Camiva.'**
  String get loginSubtitle;

  /// Primary action button on the Login screen
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginButton;

  /// Prompt to navigate to registration
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get loginNoAccount;

  /// Link to the Register screen from Login
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get loginRegisterLink;

  /// Title for the Register screen
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// Subtitle shown on the Register screen
  ///
  /// In en, this message translates to:
  /// **'Join Camiva.'**
  String get registerSubtitle;

  /// Primary action button on the Register screen
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// Prompt to navigate to login
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get registerHaveAccount;

  /// Link to the Login screen from Register
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get registerLoginLink;

  /// Label above the role selector on the Register screen
  ///
  /// In en, this message translates to:
  /// **'Tell us who you are'**
  String get registerRoleLabel;

  /// Validation message when no role is chosen at registration
  ///
  /// In en, this message translates to:
  /// **'Please choose how you will use Camiva.'**
  String get registerRolePrompt;

  /// Message shown after registration when Supabase email confirmation is enabled
  ///
  /// In en, this message translates to:
  /// **'Check your email to confirm your account, then sign in.'**
  String get registerEmailConfirmation;

  /// Label for the email input field
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// Label for the password input field
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// Label for the confirm password input field
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get fieldConfirmPassword;

  /// Label for the name input field
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fieldName;

  /// Generic required field validation message
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get validationRequired;

  /// Email format validation message
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get validationEmailInvalid;

  /// Password length validation message
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get validationPasswordTooShort;

  /// Confirm password mismatch message
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get validationPasswordMismatch;

  /// Label for the name field on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileName;

  /// Label for the email field on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileEmail;

  /// Label for the role field on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get profileRole;

  /// Logout button label on the Profile screen
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get profileLogout;

  /// Title of the logout confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get profileLogoutConfirmTitle;

  /// Body of the logout confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to access your account.'**
  String get profileLogoutConfirmBody;

  /// Confirm button in the logout dialog
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get profileLogoutConfirm;

  /// Cancel button in the logout dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileLogoutCancel;

  /// Error shown when Supabase credentials are missing
  ///
  /// In en, this message translates to:
  /// **'The app is not connected to a backend. Please contact support.'**
  String get errorBackendNotConfigured;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// Title on the onboarding role-selection screen
  ///
  /// In en, this message translates to:
  /// **'How will you use Camiva?'**
  String get onboardingTitle;

  /// Subtitle on the onboarding screen
  ///
  /// In en, this message translates to:
  /// **'Choose your role. You can update this later.'**
  String get onboardingSubtitle;

  /// Label for the name field on onboarding
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get onboardingNameLabel;

  /// Label above the role selector on onboarding
  ///
  /// In en, this message translates to:
  /// **'I am a'**
  String get onboardingRoleLabel;

  /// Primary action button on the onboarding screen
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingButton;

  /// Network error on onboarding submission
  ///
  /// In en, this message translates to:
  /// **'No connection. Please check your internet and try again.'**
  String get onboardingErrorNetwork;

  /// Shown while the profile is being fetched on launch
  ///
  /// In en, this message translates to:
  /// **'Loading your profile…'**
  String get loadingProfile;

  /// Shown when profile fetch fails on launch
  ///
  /// In en, this message translates to:
  /// **'Could not load your profile. Please check your connection.'**
  String get errorProfileLoad;

  /// Generic retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// Snackbar after a teacher request is successfully sent
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get requestSent;

  /// Status label / button state when a request is pending
  ///
  /// In en, this message translates to:
  /// **'Request pending'**
  String get requestPending;

  /// Status shown when a request has been accepted
  ///
  /// In en, this message translates to:
  /// **'Teacher connected'**
  String get requestAccepted;

  /// Status label when a request was declined
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get requestDeclined;

  /// Status label when a request was cancelled
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get requestCancelled;

  /// Button for a parent to cancel their pending request
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get requestCancelButton;

  /// Error shown when a duplicate request is attempted
  ///
  /// In en, this message translates to:
  /// **'A request has already been sent for this child and teacher.'**
  String get requestAlreadySent;

  /// Title of the parent's requests screen
  ///
  /// In en, this message translates to:
  /// **'My Requests'**
  String get parentRequestsTitle;

  /// Shown when the parent has no requests
  ///
  /// In en, this message translates to:
  /// **'You have no requests yet.'**
  String get parentRequestsEmpty;

  /// Title of the teacher's incoming requests screen
  ///
  /// In en, this message translates to:
  /// **'Teaching Requests'**
  String get teacherRequestsTitle;

  /// Shown when the teacher has no incoming requests
  ///
  /// In en, this message translates to:
  /// **'No incoming requests.'**
  String get teacherRequestsEmpty;

  /// Button for a teacher to accept a request
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get requestAcceptButton;

  /// Button for a teacher to decline a request
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get requestDeclineButton;

  /// Title of the teacher's connected students screen
  ///
  /// In en, this message translates to:
  /// **'My Students'**
  String get myStudentsTitle;

  /// Shown when the teacher has no connected students
  ///
  /// In en, this message translates to:
  /// **'You have no connected students yet.'**
  String get myStudentsEmpty;

  /// Label for the teacher section on student detail
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get studentConnectedTeacherLabel;

  /// Shown when a student has no accepted teacher
  ///
  /// In en, this message translates to:
  /// **'No teacher connected yet.'**
  String get studentNoTeacherYet;

  /// Label for child in a request row
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get requestChildLabel;

  /// Label for teacher in a request row
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get requestTeacherLabel;

  /// Label for status in a request row
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get requestStatusLabel;

  /// Navigation label for requests
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get navRequests;

  /// Button on teacher home to view incoming requests
  ///
  /// In en, this message translates to:
  /// **'Teaching Requests'**
  String get teacherHomeRequests;

  /// Button on teacher home to view connected students
  ///
  /// In en, this message translates to:
  /// **'My Students'**
  String get teacherHomeStudents;

  /// Label for a student's school form in teacher views
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get studentFormLabel;

  /// Badge shown on an accepted teacher connection
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectedBadge;

  /// Shows which child a teacher request is for
  ///
  /// In en, this message translates to:
  /// **'For {name}'**
  String requestForChild(String name);

  /// Section header for teacher location
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get teacherLocationSection;

  /// Privacy-reassuring hint for the location fields
  ///
  /// In en, this message translates to:
  /// **'Roughly where you teach. Parents see your area, never your exact address.'**
  String get teacherLocationHint;

  /// Label for the teacher city field
  ///
  /// In en, this message translates to:
  /// **'City / town'**
  String get teacherCityLabel;

  /// Label for the teacher area field
  ///
  /// In en, this message translates to:
  /// **'Neighbourhood / area (optional)'**
  String get teacherAreaLabel;

  /// Label for the location on a teacher profile
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get teacherProfileLocationLabel;

  /// Safe label for the requesting parent (identified by their child)
  ///
  /// In en, this message translates to:
  /// **'Parent of {name}'**
  String requestParentOf(String name);

  /// Hint highlighting subjects the teacher teaches
  ///
  /// In en, this message translates to:
  /// **'Matches your subjects'**
  String get requestMatchesYourSubjects;

  /// When a request was made
  ///
  /// In en, this message translates to:
  /// **'Requested {date}'**
  String requestRequestedOn(String date);

  /// Shown when a request has no child snapshot
  ///
  /// In en, this message translates to:
  /// **'Child details unavailable'**
  String get requestChildUnavailable;

  /// Generic error title
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// Generic error body
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get errorGenericBody;

  /// Empty children title
  ///
  /// In en, this message translates to:
  /// **'Add your first child'**
  String get childrenEmptyTitle;

  /// Empty children body
  ///
  /// In en, this message translates to:
  /// **'Add their Form and subjects to start finding teachers.'**
  String get childrenEmptyBody;

  /// Section header for children on parent home
  ///
  /// In en, this message translates to:
  /// **'Your children'**
  String get parentHomeChildrenSection;

  /// Section header for attention items
  ///
  /// In en, this message translates to:
  /// **'Needs your attention'**
  String get parentHomeAttentionSection;

  /// Section header for recent learning
  ///
  /// In en, this message translates to:
  /// **'Recent learning'**
  String get parentHomeLearningSection;

  /// Section header for quick actions
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// Compact child summary on home
  ///
  /// In en, this message translates to:
  /// **'{form} · {count, plural, =1{1 subject} other{{count} subjects}}'**
  String childSummary(String form, int count);

  /// Attention item for due activities
  ///
  /// In en, this message translates to:
  /// **'{name} has {count, plural, =1{1 activity} other{{count} activities}} due soon.'**
  String attentionActivityDue(String name, int count);

  /// Attention item for pending request
  ///
  /// In en, this message translates to:
  /// **'{name} has a pending teacher request.'**
  String attentionPendingRequest(String name);

  /// Section header for actionable teacher requests
  ///
  /// In en, this message translates to:
  /// **'Needs your response'**
  String get requestsNeedsResponse;

  /// Section header for accepted connections
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get requestsConnectedSection;

  /// Section header for pending parent requests
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get requestsPendingSection;

  /// Section header for past requests
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get requestsHistorySection;

  /// Teacher requests empty title
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get teacherRequestsEmptyTitle;

  /// Teacher requests empty body
  ///
  /// In en, this message translates to:
  /// **'Requests from parents will appear here.'**
  String get teacherRequestsEmptyBody;

  /// Parent requests empty title
  ///
  /// In en, this message translates to:
  /// **'No requests yet'**
  String get parentRequestsEmptyTitle;

  /// Parent requests empty body
  ///
  /// In en, this message translates to:
  /// **'Teachers you request will appear here.'**
  String get parentRequestsEmptyBody;

  /// My students empty title
  ///
  /// In en, this message translates to:
  /// **'No students yet'**
  String get myStudentsEmptyTitle;

  /// My students empty body
  ///
  /// In en, this message translates to:
  /// **'Accepted teacher connections will appear here.'**
  String get myStudentsEmptyBody;

  /// Teacher home today section
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get teacherHomeTodaySection;

  /// Teacher home pending section
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get teacherHomePendingSection;

  /// Teacher home students section
  ///
  /// In en, this message translates to:
  /// **'My students'**
  String get teacherHomeStudentsSection;

  /// Teacher today activities
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No activities today} =1{1 learning activity} other{{count} learning activities}}'**
  String teacherHomeLearningToday(int count);

  /// Teacher needs attention count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 student needs attention} other{{count} students need attention}}'**
  String teacherHomeNeedsAttention(int count);

  /// Teacher pending requests count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 teaching request} other{{count} teaching requests}}'**
  String teacherHomePendingRequests(int count);

  /// Teacher quick action
  ///
  /// In en, this message translates to:
  /// **'View students'**
  String get teacherHomeViewStudents;

  /// Teacher quick action
  ///
  /// In en, this message translates to:
  /// **'View requests'**
  String get teacherHomeViewRequests;

  /// Teacher quick action
  ///
  /// In en, this message translates to:
  /// **'Create learning activity'**
  String get teacherHomeCreateActivity;

  /// Match explanation header on teacher profile
  ///
  /// In en, this message translates to:
  /// **'Why {name} may be a good match'**
  String teacherWhyMatch(String name);

  /// Match reason: form
  ///
  /// In en, this message translates to:
  /// **'Teaches {form}'**
  String teacherMatchForm(String form);

  /// Match reason: subject
  ///
  /// In en, this message translates to:
  /// **'Teaches {subject}'**
  String teacherMatchSubject(String subject);

  /// Parent learning feed empty title
  ///
  /// In en, this message translates to:
  /// **'No learning updates yet'**
  String get learningEmptyParentTitle;

  /// Parent learning feed empty body
  ///
  /// In en, this message translates to:
  /// **'Updates from your child\'s teachers will appear here.'**
  String get learningEmptyParentBody;

  /// Quick action to find a teacher
  ///
  /// In en, this message translates to:
  /// **'Find a teacher'**
  String get findTeacherAction;

  /// Teacher home greeting subtitle
  ///
  /// In en, this message translates to:
  /// **'Your teaching workspace'**
  String get teacherHomeSubtitle;

  /// Main header on the discovery screen
  ///
  /// In en, this message translates to:
  /// **'Find a teacher for {name}'**
  String discoveryHeaderTitle(String name);

  /// Map/List toggle — map option
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get discoveryViewMap;

  /// Map/List toggle — list option
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get discoveryViewList;

  /// Toggle to sort teachers by distance
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get discoveryNearby;

  /// Filter to teachers who can teach online
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get discoveryOnline;

  /// Subject filter label
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get discoveryFilterSubject;

  /// Form filter label
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get discoveryFilterForm;

  /// Subject filter — no subject selected
  ///
  /// In en, this message translates to:
  /// **'All subjects'**
  String get discoveryFilterAllSubjects;

  /// Form filter — no form selected
  ///
  /// In en, this message translates to:
  /// **'All forms'**
  String get discoveryFilterAllForms;

  /// Clear the active discovery filters
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get discoveryClearFilters;

  /// Section label when sorted by distance
  ///
  /// In en, this message translates to:
  /// **'Teachers near you'**
  String get discoveryNearYou;

  /// Section label when location is unavailable but a city is known
  ///
  /// In en, this message translates to:
  /// **'Teachers in {city}'**
  String discoveryInCity(String city);

  /// Generic section label for the teacher list
  ///
  /// In en, this message translates to:
  /// **'Relevant teachers'**
  String get discoveryRelevantTeachers;

  /// Count of teachers shown
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 teacher} other{{count} teachers}}'**
  String discoveryResultCount(int count);

  /// Badge on the single strongest match
  ///
  /// In en, this message translates to:
  /// **'Best match'**
  String get discoveryBestMatch;

  /// Shown while the device location is resolved
  ///
  /// In en, this message translates to:
  /// **'Finding teachers near you…'**
  String get discoveryLocating;

  /// Button to enable Nearby via device location
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get discoveryUseMyLocation;

  /// Empty state when nearby has no results
  ///
  /// In en, this message translates to:
  /// **'No teachers found nearby'**
  String get discoveryEmptyNearbyTitle;

  /// Guidance for the nearby empty state
  ///
  /// In en, this message translates to:
  /// **'Try another subject, Form, or view all teachers.'**
  String get discoveryEmptyNearbyBody;

  /// Reset filters and show every relevant teacher
  ///
  /// In en, this message translates to:
  /// **'View all teachers'**
  String get discoveryViewAll;

  /// Title when device location can't be used
  ///
  /// In en, this message translates to:
  /// **'Location isn\'t available'**
  String get discoveryLocationUnavailableTitle;

  /// Reassurance when location is unavailable
  ///
  /// In en, this message translates to:
  /// **'You can still browse teachers in your area.'**
  String get discoveryLocationUnavailableBody;

  /// Title when the map tiles fail
  ///
  /// In en, this message translates to:
  /// **'Map couldn\'t load'**
  String get discoveryMapUnavailableTitle;

  /// Fallback guidance when the map fails
  ///
  /// In en, this message translates to:
  /// **'Browse teachers in the list instead.'**
  String get discoveryMapUnavailableBody;

  /// Shown for a teacher with a city but no map pin
  ///
  /// In en, this message translates to:
  /// **'Approximate area only'**
  String get discoveryNoMapForTeacher;

  /// Short map attribution
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap'**
  String get discoveryMapAttributionOsm;

  /// Privacy note next to a teacher's location
  ///
  /// In en, this message translates to:
  /// **'Teaching area — not a home address.'**
  String get teacherServiceAreaNote;

  /// Label for teaching mode on a profile
  ///
  /// In en, this message translates to:
  /// **'Teaching mode'**
  String get teacherTeachingModeLabel;

  /// Teaching mode: online only
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get teacherTeachingModeOnline;

  /// Teaching mode: in person only
  ///
  /// In en, this message translates to:
  /// **'In person'**
  String get teacherTeachingModeInPerson;

  /// Teaching mode: both
  ///
  /// In en, this message translates to:
  /// **'Online + In person'**
  String get teacherTeachingModeBoth;

  /// Section header for teaching mode in profile editing
  ///
  /// In en, this message translates to:
  /// **'How do you teach?'**
  String get teacherModeQuestion;

  /// Hint under the teaching mode selector
  ///
  /// In en, this message translates to:
  /// **'Parents will see whether you can teach in person, online, or both.'**
  String get teacherModeHint;

  /// Section header for optional coordinate pinning
  ///
  /// In en, this message translates to:
  /// **'Approximate map location (optional)'**
  String get teacherPinAreaTitle;

  /// Explains coarse coordinate pinning before requesting location
  ///
  /// In en, this message translates to:
  /// **'Add a rough pin so parents can see your area on the map. We round it so it never shows your exact address.'**
  String get teacherPinAreaHint;

  /// Button to set approximate coordinates from device location
  ///
  /// In en, this message translates to:
  /// **'Use my current area'**
  String get teacherPinAreaButton;

  /// Confirmation that coarse coordinates were captured
  ///
  /// In en, this message translates to:
  /// **'Approximate area set'**
  String get teacherPinAreaSet;

  /// Remove the approximate coordinates
  ///
  /// In en, this message translates to:
  /// **'Remove pin'**
  String get teacherPinAreaClear;

  /// Shown when location permission is denied during pinning
  ///
  /// In en, this message translates to:
  /// **'Location permission is off. You can still enter your city and area above.'**
  String get teacherPinAreaDenied;

  /// Match explanation header with both teacher and child names
  ///
  /// In en, this message translates to:
  /// **'Why {teacherName} is a good match for {childName}'**
  String teacherWhyMatchFor(String teacherName, String childName);

  /// Match reason: teacher covers the area
  ///
  /// In en, this message translates to:
  /// **'Covers {area}'**
  String teacherMatchArea(String area);

  /// Button to change profile photo
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get profilePhotoChange;

  /// Button to remove profile photo
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profilePhotoRemove;

  /// Button to upload a profile photo
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get profilePhotoUpload;

  /// Shown while a profile photo is being uploaded
  ///
  /// In en, this message translates to:
  /// **'Uploading photo…'**
  String get profilePhotoUploading;

  /// Error when photo upload or removal fails
  ///
  /// In en, this message translates to:
  /// **'Could not update photo. Please try again.'**
  String get profilePhotoError;

  /// Snackbar after photo is removed
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get profilePhotoRemoved;

  /// Snackbar after photo is uploaded
  ///
  /// In en, this message translates to:
  /// **'Photo updated'**
  String get profilePhotoUpdated;

  /// Label shown on a teacher profile indicating home/physical tutoring
  ///
  /// In en, this message translates to:
  /// **'Home Tutor'**
  String get homeTutorLabel;

  /// Section header for home tutoring information
  ///
  /// In en, this message translates to:
  /// **'Home tutoring'**
  String get homeTutoringSection;

  /// Badge indicating teacher provides home tutoring
  ///
  /// In en, this message translates to:
  /// **'In-home tutoring'**
  String get homeTutoringBadge;

  /// Section header for teaching areas
  ///
  /// In en, this message translates to:
  /// **'Teaching areas'**
  String get teacherAreasSection;

  /// Section header for reviews
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviewsSection;

  /// Empty state when there are no reviews
  ///
  /// In en, this message translates to:
  /// **'No reviews yet'**
  String get reviewsEmptyTitle;

  /// Section header for qualifications
  ///
  /// In en, this message translates to:
  /// **'Qualifications'**
  String get qualificationsSection;

  /// Shown when qualifications are not available
  ///
  /// In en, this message translates to:
  /// **'Not listed yet.'**
  String get qualificationsEmpty;

  /// Section header for teaching experience
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get experienceSection;

  /// Section header for account settings
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileAccountSection;

  /// Button to edit teaching availability
  ///
  /// In en, this message translates to:
  /// **'Edit availability'**
  String get profileEditAvailability;

  /// Primary CTA on public teacher profile
  ///
  /// In en, this message translates to:
  /// **'Request this teacher'**
  String get requestThisTeacher;

  /// Section header for availability
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get availabilitySection;

  /// Phone number field label on sign in and sign up
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get fieldPhone;

  /// PIN field label
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get fieldPin;

  /// Second PIN field on sign up
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get fieldPinConfirm;

  /// Shown for a malformed phone number
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number, e.g. 670 00 00 00.'**
  String get validationPhoneInvalid;

  /// Shown for a malformed PIN
  ///
  /// In en, this message translates to:
  /// **'Your PIN must be 4 to 6 digits.'**
  String get validationPinInvalid;

  /// Shown when the confirmation PIN differs
  ///
  /// In en, this message translates to:
  /// **'The two PINs do not match.'**
  String get validationPinMismatch;

  /// Helper text under the PIN field on sign up
  ///
  /// In en, this message translates to:
  /// **'Choose 4 to 6 digits you will remember.'**
  String get pinHelper;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
